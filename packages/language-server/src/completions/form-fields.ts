import { CompletionItem, CompletionItemKind } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { SchemaRegistry } from '../schema-registry';
import { ComponentsRegistry } from '../components-registry';
import { getComponentUsageStack, ComponentUsage } from '../utils/component-usage';

export function getFormFieldCompletions(
  document: TextDocument,
  text: string,
  offset: number,
  linePrefix: string,
  schemaRegistry: SchemaRegistry,
  componentsRegistry: ComponentsRegistry,
  templatePath: string
): CompletionItem[] | null {
  const match = /([a-zA-Z_][a-zA-Z0-9_]*)\[\s*:(\w*)$/i.exec(linePrefix);
  if (!match) {
    return null;
  }

  const variableName = match[1];
  const partial = match[2] ?? '';

  const usageStack = getComponentUsageStack(text, offset, templatePath);
  if (usageStack.length === 0) {
    return null;
  }

  const bindings = buildFormBindings(
    usageStack,
    text,
    schemaRegistry,
    componentsRegistry,
    templatePath
  );
  const schemaModule = bindings.get(variableName);
  if (!schemaModule) {
    return null;
  }

  const schema = schemaRegistry.getSchema(schemaModule);
  if (!schema) {
    return null;
  }

  const candidateFields =
    partial.length > 0
      ? schema.fields.filter(field => field.name.startsWith(partial))
      : schema.fields;
  const fields = candidateFields.length > 0 ? candidateFields : schema.fields;

  return fields.map((field, index) => ({
    label: field.name,
    kind: CompletionItemKind.Field,
    detail: field.elixirType ? `Assoc: ${field.elixirType}` : `:${field.type}`,
    documentation: field.elixirType
      ? `Association field \`${field.name}\` -> ${field.elixirType}`
      : `Schema field \`${field.name}\` (${field.type})`,
    insertText: field.name,
    sortText: `!0${index.toString().padStart(3, '0')}`,
  }));
}

function buildFormBindings(
  usageStack: ComponentUsage[],
  text: string,
  schemaRegistry: SchemaRegistry,
  componentsRegistry: ComponentsRegistry,
  templatePath: string
): Map<string, string> {
  const bindings = new Map<string, string>();

  for (const usage of usageStack) {
    const component = componentsRegistry.resolveComponent(templatePath, usage.componentName, {
      moduleContext: usage.moduleContext,
      fileContent: text,
    });
    if (!component || component.moduleName !== 'Phoenix.Component') {
      continue;
    }

    if (component.name === 'form') {
      const letAttr = usage.attributes.find(attr => attr.name === ':let');
      const forAttr = usage.attributes.find(attr => attr.name === 'for');
      if (!letAttr || !letAttr.valueText || !forAttr || !forAttr.valueText) {
        continue;
      }

      const boundVar = parseLetBinding(letAttr.valueText);
      const schemaModule = resolveSchemaModule(forAttr.valueText, schemaRegistry);
      if (boundVar && schemaModule) {
        bindings.set(boundVar, schemaModule);
      }
      continue;
    }

    if (component.name === 'inputs_for') {
      const letAttr = usage.attributes.find(attr => attr.name === ':let');
      if (!letAttr || !letAttr.valueText) {
        continue;
      }
      const boundVar = parseLetBinding(letAttr.valueText);
      if (!boundVar) {
        continue;
      }

      let schemaModule: string | null = null;
      const fieldAttr = usage.attributes.find(attr => attr.name === 'field');
      if (fieldAttr?.valueText) {
        const expr = parseInputsForField(fieldAttr.valueText);
        if (expr) {
          const baseSchema = bindings.get(expr.baseVar);
          if (baseSchema) {
            schemaModule = resolveAssociationPath(baseSchema, expr.path, schemaRegistry);
          }
        }
      }

      if (!schemaModule) {
        const forAttr = usage.attributes.find(attr => attr.name === 'for');
        if (forAttr?.valueText) {
          schemaModule = resolveSchemaModule(forAttr.valueText, schemaRegistry);
        }
      }

      if (schemaModule) {
        bindings.set(boundVar, schemaModule);
      }
    }
  }

  return bindings;
}

function parseLetBinding(value: string): string | null {
  const trimmed = value.trim();
  const match = /^\{\s*([a-zA-Z_][a-zA-Z0-9_]*)/.exec(trimmed);
  return match ? match[1] : null;
}

function stripValueDelimiters(value: string): string {
  let trimmed = value.trim();
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']')) ||
      (trimmed.startsWith('(') && trimmed.endsWith(')'))) {
    trimmed = trimmed.slice(1, -1);
  }
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith('\'') && trimmed.endsWith('\''))
  ) {
    trimmed = trimmed.slice(1, -1);
  }
  return trimmed.trim();
}

interface FieldExpression {
  baseVar: string;
  path: string[];
}

function parseInputsForField(value: string): FieldExpression | null {
  const inner = stripValueDelimiters(value);
  const pattern = /^([a-zA-Z_][a-zA-Z0-9_]*)(\s*\[\s*:[a-zA-Z_][a-zA-Z0-9_]*\s*\])+$/;
  const match = pattern.exec(inner);
  if (!match) {
    return null;
  }

  const baseVar = match[1];
  const path: string[] = [];
  const segmentPattern = /\[\s*:(\w+)\s*\]/g;
  segmentPattern.lastIndex = baseVar.length;
  let segmentMatch: RegExpExecArray | null;
  while ((segmentMatch = segmentPattern.exec(inner)) !== null) {
    path.push(segmentMatch[1]);
  }

  return { baseVar, path };
}

function resolveAssociationPath(
  baseSchema: string,
  path: string[],
  schemaRegistry: SchemaRegistry
): string | null {
  let current: string | null = baseSchema;

  for (const segment of path) {
    if (!current) {
      return null;
    }
    current = resolveAssociationTarget(current, segment, schemaRegistry);
    if (!current) {
      return null;
    }
  }

  return current;
}

function resolveAssociationTarget(
  schemaModule: string,
  fieldName: string,
  schemaRegistry: SchemaRegistry
): string | null {
  const schema = schemaRegistry.getSchema(schemaModule);
  if (!schema) {
    return null;
  }

  const associationModule = schema.associations.get(fieldName);
  if (associationModule) {
    const resolved = schemaRegistry.resolveTypeName(associationModule, schemaModule);
    return resolved || associationModule;
  }

  const field = schema.fields.find(f => f.name === fieldName);
  if (field?.elixirType) {
    const resolved = schemaRegistry.resolveTypeName(field.elixirType, schemaModule);
    return resolved || field.elixirType;
  }

  return null;
}

function resolveSchemaModule(value: string, schemaRegistry: SchemaRegistry): string | null {
  const candidates: string[] = [];

  const trimmed = value.trim();
  const atomMatch = /^:(\w+)/.exec(trimmed);
  if (atomMatch) {
    candidates.push(atomMatch[1]);
  }

  const assignMatch = /@([a-z_][a-z0-9_]*)/i.exec(trimmed);
  if (assignMatch) {
    candidates.push(assignMatch[1]);
  }

  for (const candidate of candidates) {
    const camel = candidate
      .split('_')
      .map(part => part.charAt(0).toUpperCase() + part.slice(1))
      .join('');
    const resolved = schemaRegistry.resolveTypeName(camel);
    if (resolved) {
      return resolved;
    }

    const fallback = schemaRegistry.getAllSchemas().find(schema =>
      schema.moduleName.endsWith(`.${camel}`) || schema.moduleName === camel
    );
    if (fallback) {
      return fallback.moduleName;
    }
  }

  return null;
}
