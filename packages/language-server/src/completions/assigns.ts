import { CompletionItem, CompletionItemKind, InsertTextFormat } from 'vscode-languageserver/node';
import {
  ComponentsRegistry,
  ComponentAttribute,
  getAttributeTypeDisplay
} from '../components-registry';
import { SchemaRegistry } from '../schema-registry';
import { ControllersRegistry } from '../controllers-registry';
import { findEnclosingForLoop } from '../utils/for-loop-parser';

// Debug helper - only logs if PHOENIX_PULSE_DEBUG includes 'assigns'
const debugLog = (message: string, ...args: any[]) => {
  if (process.env.PHOENIX_PULSE_DEBUG?.includes('assigns')) {
    console.log(message, ...args);
  }
};

/**
 * Check if cursor is in an @ context (e.g., @█ or @var█ or @user.profile.█)
 * Must exclude module attributes like @doc, @moduledoc, @type, etc.
 * Supports nested property access like @user.profile.address
 */
export function isAtSignContext(linePrefix: string): boolean {
  // Match @ followed by optional property chain (e.g., @user.profile.name)
  // Pattern: @ + identifier + optional (.identifier)* + optional trailing dot
  // NOTE: No \s*$ at end - allows partial word matching (e.g., @event.pro)
  const atSignPattern = /@([a-z_][a-z0-9_]*)?(?:\.([a-z_][a-z0-9_.]*))?\.?$/;
  const match = atSignPattern.exec(linePrefix);

  if (!match) {
    return false;
  }

  const word = match[1] || '';

  // Exclude known module attributes
  const moduleAttributes = [
    'doc', 'moduledoc', 'type', 'spec', 'callback', 'impl',
    'behaviour', 'typedoc', 'dialyzer', 'deprecated', 'since',
    'vsn', 'on_load', 'on_definition', 'before_compile', 'after_compile',
    'external_resource', 'file', 'compile', 'derive'
  ];

  if (!word) {
    return true; // Allow completion immediately after typing @
  }

  return !moduleAttributes.includes(word);
}

/**
 * Check if cursor is in an assigns. context (e.g., assigns.█ or assigns.user.profile.█)
 * Supports nested property access like assigns.user.profile.address
 */
export function isAssignsContext(linePrefix: string): boolean {
  // Match assigns. followed by optional property chain
  // Pattern: assigns. + identifier + optional (.identifier)* + optional trailing dot
  // NOTE: No \s*$ at end - allows partial word matching (e.g., assigns.event.prod)
  const pattern = /assigns\.([a-z_][a-z0-9_.]*)?\.?$/;
  const matches = pattern.test(linePrefix);

  // Debug logging
  if (linePrefix.includes('assigns.')) {
    console.log('[isAssignsContext] linePrefix:', JSON.stringify(linePrefix));
    console.log('[isAssignsContext] matches:', matches);
  }

  return matches;
}

/**
 * Check if cursor is completing a :for loop variable (e.g., {image.█} inside :for={image <- @list})
 * This requires checking both the linePrefix AND the full document context
 */
export function isForLoopVariableContext(linePrefix: string, text: string, offset: number): boolean {
  debugLog('[isForLoopVariableContext] linePrefix:', JSON.stringify(linePrefix));

  // Quick pattern check: {varName. or varName. (without @ or assigns.)
  // Must be a simple identifier followed by dot, not starting with @
  const simpleVarPattern = /\{?([a-z_][a-z0-9_]*)\.([a-z0-9_.]*)\.?$/;
  const match = simpleVarPattern.exec(linePrefix);

  if (!match) {
    debugLog('[isForLoopVariableContext] No simple var pattern match');
    return false;
  }

  const varName = match[1];
  debugLog('[isForLoopVariableContext] Potential loop var:', varName);

  // Check if this variable is actually a :for loop variable
  const { findEnclosingForLoop } = require('../utils/for-loop-parser');
  const forLoop = findEnclosingForLoop(text, offset);

  if (forLoop && forLoop.variable) {
    const isLoopVar = forLoop.variable.name === varName;
    debugLog('[isForLoopVariableContext] Found :for loop:', forLoop.variable.name, 'matches:', isLoopVar);
    return isLoopVar;
  }

  debugLog('[isForLoopVariableContext] No enclosing :for loop found');
  return false;
}

/**
 * Extract the property path from @ or assigns. context
 * Examples:
 *   "@user" -> { base: "user", path: [] }
 *   "@user.profile" -> { base: "user", path: ["profile"] }
 *   "@user.profile.address." -> { base: "user", path: ["profile", "address"] }
 *   "assigns.user.profile" -> { base: "user", path: ["profile"] }
 */
export function extractPropertyPath(linePrefix: string): { base: string; path: string[] } | null {
  // Try @ pattern first
  // NOTE: No \s*$ at end - allows partial word matching (e.g., @event.pro)
  const atPattern = /@([a-z_][a-z0-9_]*)?(?:\.([a-z_][a-z0-9_.]*))?\.?$/;
  const atMatch = atPattern.exec(linePrefix);

  if (atMatch) {
    const base = atMatch[1] || '';
    const rest = atMatch[2] || '';
    const path = rest ? rest.split('.').filter(p => p.length > 0) : [];
    return { base, path };
  }

  // Try assigns. pattern
  // NOTE: No \s*$ at end - allows partial word matching
  const assignsPattern = /assigns\.([a-z_][a-z0-9_.]*)?\.?$/;
  const assignsMatch = assignsPattern.exec(linePrefix);

  if (assignsMatch) {
    const rest = assignsMatch[1] || '';
    if (!rest) {
      debugLog('[extractPropertyPath] assigns. with no property yet');
      return { base: '', path: [] };
    }
    const parts = rest.split('.').filter(p => p.length > 0);
    const base = parts[0] || '';
    const path = parts.slice(1);

    debugLog('[extractPropertyPath] linePrefix:', JSON.stringify(linePrefix));
    debugLog('[extractPropertyPath] result:', { base, path });

    return { base, path };
  }

  // Try :for loop variable pattern (e.g., {image.url or image.url)
  // This pattern matches simple variable names (no @ or assigns.)
  const forVarPattern = /\{?([a-z_][a-z0-9_]*)\.([a-z0-9_.]*)\.?$/;
  const forVarMatch = forVarPattern.exec(linePrefix);

  if (forVarMatch) {
    const base = forVarMatch[1];
    const rest = forVarMatch[2] || '';
    const path = rest ? rest.split('.').filter(p => p.length > 0) : [];

    debugLog('[extractPropertyPath] :for loop variable pattern:', { base, path });
    return { base, path };
  }

  return null;
}

/**
 * Get assign completions for @ and assigns. contexts
 * Supports nested property access using schema registry
 *
 * @param componentsRegistry - The components registry
 * @param schemaRegistry - The schema registry
 * @param filePath - Path to current file
 * @param offset - Character offset in the file
 * @param text - Full document text
 * @param linePrefix - Text before cursor on current line
 * @returns Array of completion items for component attributes or schema fields
 */
export function getAssignCompletions(
  componentsRegistry: ComponentsRegistry,
  schemaRegistry: SchemaRegistry,
  controllersRegistry: ControllersRegistry,
  filePath: string,
  offset: number,
  text: string,
  linePrefix: string
): CompletionItem[] {
  debugLog('[getAssignCompletions] called with linePrefix:', JSON.stringify(linePrefix));

  const completions: CompletionItem[] = [];

  // Extract the property path from the linePrefix
  const propertyPath = extractPropertyPath(linePrefix);
  debugLog('[getAssignCompletions] propertyPath:', propertyPath);

  if (!propertyPath) {
    return completions;
  }

  let { base, path } = propertyPath;

  // EARLY CHECK: Is the user completing a :for loop variable?
  // e.g., <div :for={image <- @product.images}> ... {image.█} ...
  // This must come BEFORE other checks to prevent treating "image" as a regular assign
  const forLoop = findEnclosingForLoop(text, offset);

  if (forLoop && forLoop.variable) {
    const loopVar = forLoop.variable;

    // Check if we're completing the loop variable (e.g., image.url)
    if (base === loopVar.name && base.length > 0) {
      debugLog('[getAssignCompletions] Detected :for loop variable:', loopVar.name);
      debugLog('[getAssignCompletions] Source:', loopVar.source);

      // Infer the type of the loop variable
      // @product.images → Product → images field (has_many) → ProductImage
      const { inferAssignType } = require('../utils/type-inference');
      const baseType = inferAssignType(
        componentsRegistry,
        controllersRegistry,
        schemaRegistry,
        filePath,
        loopVar.baseAssign,
        offset,
        text
      );

      if (baseType) {
        debugLog('[getAssignCompletions] Loop base type:', baseType);

        // Determine the target type for the loop variable
        let targetType: string | null = null;

        if (loopVar.path.length === 0) {
          // Direct list access: raffle <- @raffles
          // The baseType is already the type of each item in the list
          debugLog('[getAssignCompletions] Direct list access - using baseType as targetType');
          targetType = baseType;
        } else {
          // Field access: image <- @product.images OR image <- product.images
          const baseSchema = schemaRegistry.getSchema(baseType);

          if (!baseSchema) {
            debugLog('[getAssignCompletions] Could not find schema for base type:', baseType);
            return completions; // Early return
          }

          // Get the field that the loop is iterating over
          const loopField = baseSchema.fields.find(f => f.name === loopVar.path[0]);

          if (!loopField) {
            debugLog('[getAssignCompletions] :for loop field not found:', loopVar.path[0]);
            return completions; // Early return - avoid falling through to component logic
          }

          if (!loopField.elixirType) {
            debugLog('[getAssignCompletions] :for loop field has no elixirType');
            return completions; // Early return
          }

          debugLog('[getAssignCompletions] Loop field type:', loopField.elixirType);

          // Resolve the target type (ProductImage)
          targetType = schemaRegistry.resolveTypeName(loopField.elixirType, baseSchema.moduleName);
          if (!targetType) {
            debugLog('[getAssignCompletions] Could not resolve target type for:', loopField.elixirType);
            return completions; // Early return
          }
        }

        debugLog('[getAssignCompletions] Loop variable type:', targetType);

        // Get fields from the target schema
        let fields: any[] = [];
        if (path.length === 0) {
          // Top-level fields (raffle.█ or image.█)
          const targetSchema = schemaRegistry.getSchema(targetType);
          if (targetSchema) {
            fields = targetSchema.fields;
          }
        } else {
          // Nested fields (raffle.product.█ or image.product.█)
          fields = schemaRegistry.getFieldsForPath(targetType, path);
        }

        debugLog('[getAssignCompletions] Loop variable fields:', fields.length);

        // Return completions for loop variable fields
        fields.forEach((field, index) => {
          const item: CompletionItem = {
            label: field.name,
            kind: field.elixirType ? CompletionItemKind.Reference : CompletionItemKind.Field,
            detail: field.elixirType || `:${field.type}`,
            documentation: field.elixirType
              ? `Association: ${field.elixirType}`
              : `Field type: :${field.type}`,
            insertText: field.name,
            sortText: `!0${index.toString().padStart(3, '0')}`,
          };
          completions.push(item);
        });

        return completions;
      } else {
        debugLog('[getAssignCompletions] Could not infer base type for:', loopVar.baseAssign);
        return completions; // Early return - this is a loop variable but we can't resolve it
      }
    }
  }

  // Check if user is requesting nested completions (has trailing dot)
  const trimmedPrefix = linePrefix.trimEnd();
  const requestingNested = trimmedPrefix.endsWith('.') && (base.length > 0 || path.length > 0);

  // CRITICAL FIX: If not requesting nested (no trailing dot) and path has items,
  // the last segment is incomplete (e.g., "assigns.event.prod" -> "prod" is partial).
  // Pop it off so we show completions for "event", not drill into "prod".
  // VSCode will filter the results based on the partial text.
  if (!requestingNested && path.length > 0) {
    debugLog('[getAssignCompletions] Popping incomplete segment from path:', path[path.length - 1]);
    path = path.slice(0, -1);
  }

  debugLog('[getAssignCompletions] base:', base, 'path:', path, 'requestingNested:', requestingNested);

  // Get attributes for the current component scope
  const component = componentsRegistry.getCurrentComponent(filePath, offset, text);
  debugLog('[getAssignCompletions] component found:', !!component);

  if (component) {
    debugLog('[getAssignCompletions] Inside component branch, path.length:', path.length, 'base:', base);
    const attributes = component.attributes;
    const slots = component.slots;

    // Only return component attrs/slots when no base (typing "assigns." or "@")
    // If base exists (e.g., "assigns.event"), continue to schema lookup below
    if (path.length === 0 && !requestingNested && !base) {
      debugLog('[getAssignCompletions] Returning component attrs/slots');
      attributes.forEach((attr, index) => {
        const typeDisplay = getAttributeTypeDisplay(attr);
        const item: CompletionItem = {
          label: attr.name,
          kind: CompletionItemKind.Property,
          detail: `${typeDisplay}${attr.required ? ' (required)' : ''}${attr.default ? ` = ${attr.default}` : ''}`,
          documentation: buildAttributeDocumentation(attr),
          insertText: attr.name,
          sortText: `!0${index.toString().padStart(3, '0')}`,
        };
        completions.push(item);
      });

      slots.forEach((slot, index) => {
        const item: CompletionItem = {
          label: slot.name,
          kind: CompletionItemKind.Interface,
          detail: `Slot${slot.required ? ' (required)' : ''}`,
          documentation: slot.doc
            ? `${slot.doc}\n\nUse with \`render_slot(@${slot.name})\` or \`<:${slot.name}>\`.`
            : `Slot for component <.${component.name}>. Use with \`render_slot(@${slot.name})\` or \`<:${slot.name}>\`.`,
          insertText: slot.name,
          sortText: `!2${index.toString().padStart(3, '0')}`,
        };
        completions.push(item);
      });

      return completions;
    }

    const baseAttr = attributes.find(attr => attr.name === base);
    debugLog('[getAssignCompletions] Looking for baseAttr:', base, 'found:', !!baseAttr);

    if (!baseAttr) {
      debugLog('[getAssignCompletions] baseAttr not found, returning empty');
      return completions;
    }

    let baseTypeName: string | null = null;

    if (baseAttr.type.match(/^[A-Z]/)) {
      baseTypeName = schemaRegistry.resolveTypeName(baseAttr.type);
    }

    // Also try rawType if available
    if (!baseTypeName && baseAttr.rawType && baseAttr.rawType.match(/^[A-Z]/)) {
      baseTypeName = schemaRegistry.resolveTypeName(baseAttr.rawType);
    }

    if (!baseTypeName) {
      const guessedType = base.split('_').map(part =>
        part.charAt(0).toUpperCase() + part.slice(1)
      ).join('');
      baseTypeName = schemaRegistry.resolveTypeName(guessedType);
    }

    debugLog('[getAssignCompletions] Resolved baseTypeName:', baseTypeName);

    if (!baseTypeName) {
      debugLog('[getAssignCompletions] No baseTypeName, returning empty');
      return completions;
    }

    // Get schema and verify it exists
    let schema = schemaRegistry.getSchema(baseTypeName);
    debugLog('[getAssignCompletions] Schema found:', !!schema, 'for type:', baseTypeName);

    if (!schema) {
      debugLog('[getAssignCompletions] No schema, returning empty');
      return completions;
    }

    let fields = [];
    let isListField = false;

    if (path.length === 0) {
      fields = schema.fields;
      debugLog('[getAssignCompletions] Getting top-level fields, count:', fields.length);
    } else {
      // Check if we're trying to drill into a list field (has_many, embeds_many)
      // Walk the path and check each field
      let currentSchema = schema;
      for (let i = 0; i < path.length; i++) {
        const segment = path[i];
        const field = currentSchema.fields.find(f => f.name === segment);

        if (!field) {
          break; // Field not found, getFieldsForPath will return empty
        }

        // Check if this is a list field
        if (field.type === 'list' && i === path.length - 1) {
          isListField = true;
          debugLog('[getAssignCompletions] Detected list field:', segment, '- use :for loop to iterate');
          break;
        }

        // Continue to next level if there's an association
        if (field.elixirType) {
          const nextTypeName = schemaRegistry.resolveTypeName(field.elixirType, currentSchema.moduleName);
          const nextSchema = nextTypeName ? schemaRegistry.getSchema(nextTypeName) : null;
          if (!nextSchema) {
            break;
          }
          currentSchema = nextSchema;
        }
      }

      if (!isListField) {
        fields = schemaRegistry.getFieldsForPath(baseTypeName, path);
        debugLog('[getAssignCompletions] Getting nested fields for path:', path, 'count:', fields.length);
      }
    }

    if (isListField) {
      // Provide helpful completion items for list operations
      const listOps = [
        {
          label: 'Use :for loop →',
          kind: CompletionItemKind.Text,
          detail: 'Lists must be iterated',
          documentation: `Use :for to iterate:\n\n<div :for={item <- @${base}.${path.join('.')}}>\n  {item.field}\n</div>`,
          insertText: '',
          sortText: '!0000',
        },
      ];
      completions.push(...listOps);
    } else {
      fields.forEach((field, index) => {
        const item: CompletionItem = {
          label: field.name,
          kind: field.elixirType ? CompletionItemKind.Reference : CompletionItemKind.Field,
          detail: field.elixirType || `:${field.type}`,
          documentation: field.elixirType
            ? `Association: ${field.elixirType}`
            : `Field type: :${field.type}`,
          insertText: field.name,
          sortText: `!0${index.toString().padStart(3, '0')}`,
        };
        completions.push(item);
      });
    }

    return completions;
  }

  const templateSummary = controllersRegistry.getTemplateSummary(filePath);
  if (!templateSummary) {
    return completions;
  }

  const assignNames = Array.from(templateSummary.assignSources.keys()).sort();
  if (assignNames.length === 0) {
    return completions;
  }

  if (path.length === 0 && !requestingNested) {
    assignNames.forEach((assignName, index) => {
      const sources = templateSummary.assignSources.get(assignName) || [];

      // Get type info from the first source that has it
      let typeDetail = 'Controller assign';
      let typeDoc = '';

      for (const source of sources) {
        if (source.assignsWithTypes) {
          const assignInfo = source.assignsWithTypes.find(a => a.name === assignName);
          if (assignInfo?.typeInfo) {
            // Format the type information
            if (assignInfo.typeInfo.kind === 'struct' && assignInfo.typeInfo.module) {
              typeDetail = `%${assignInfo.typeInfo.module}{}`;
              typeDoc = `Type: ${typeDetail}\n\n`;
            } else if (assignInfo.typeInfo.kind === 'list' && assignInfo.typeInfo.innerType?.module) {
              typeDetail = `[%${assignInfo.typeInfo.innerType.module}{}]`;
              typeDoc = `Type: ${typeDetail}\n\n`;
            } else if (assignInfo.typeInfo.kind === 'changeset') {
              typeDetail = '%Ecto.Changeset{}';
              typeDoc = `Type: ${typeDetail}\n\n`;
            }
            break;
          }
        }
      }

      const sourceDocs = sources
        .map(source => {
          if (source.action) {
            return `${source.controllerModule}.${source.action}`;
          }
          return source.controllerModule;
        })
        .filter((value, idx, arr) => arr.indexOf(value) === idx)
        .join('\n');

      const item: CompletionItem = {
        label: assignName,
        kind: CompletionItemKind.Property,
        detail: typeDetail,
        documentation: typeDoc + (sourceDocs
          ? `Assigned in:\n${sourceDocs}`
          : 'Assigned via controller render call.'),
        insertText: assignName,
        sortText: `!0${index.toString().padStart(3, '0')}`,
      };
      completions.push(item);
    });

    return completions;
  }

  if (!base || !assignNames.includes(base)) {
    return completions;
  }

  // Try to get the schema module from typed assign info first
  let schemaModule: string | null = null;

  const sources = templateSummary.assignSources.get(base) || [];
  for (const source of sources) {
    if (source.assignsWithTypes) {
      const assignInfo = source.assignsWithTypes.find(a => a.name === base);
      if (assignInfo?.typeInfo) {
        // Extract module from type info
        if (assignInfo.typeInfo.kind === 'struct' && assignInfo.typeInfo.module) {
          schemaModule = assignInfo.typeInfo.module;
          break;
        } else if (assignInfo.typeInfo.kind === 'list' && assignInfo.typeInfo.innerType?.module) {
          // For lists, we want to complete on the inner type
          schemaModule = assignInfo.typeInfo.innerType.module;
          break;
        }
      }
    }
  }

  // Fallback to name-based resolution if we don't have type info
  if (!schemaModule) {
    schemaModule = resolveSchemaFromAssignName(schemaRegistry, base);
  }

  if (!schemaModule) {
    return completions;
  }

  // Verify schema exists, try fallbacks if it doesn't
  let schema = schemaRegistry.getSchema(schemaModule);

  if (!schema && schemaModule.includes('.')) {
    // Type inference might have guessed wrong (e.g., Catalog.FeaturedProduct instead of Catalog.Product)
    // Try variations:
    // 1. Strip adjectives: "Catalog.FeaturedProduct" -> "Catalog.Product"
    // 2. Check all schemas in the same context module
    const parts = schemaModule.split('.');
    const contextModule = parts.slice(0, -1).join('.'); // e.g., "Catalog"
    const inferredName = parts[parts.length - 1]; // e.g., "FeaturedProduct"

    // Try: Strip everything before last capitalized word
    // "FeaturedProduct" -> "Product", "AdminUser" -> "User"
    const simplifiedMatch = inferredName.match(/([A-Z][a-z]+)$/);
    if (simplifiedMatch && contextModule) {
      const simplifiedModule = `${contextModule}.${simplifiedMatch[1]}`;
      schema = schemaRegistry.getSchema(simplifiedModule);
      if (schema) {
        schemaModule = simplifiedModule;
      }
    }

    // Still not found? Try finding ANY schema in the same context module
    if (!schema && contextModule) {
      const allSchemas = schemaRegistry.getAllSchemas();
      const contextSchemas = allSchemas.filter(s => s.moduleName.includes(contextModule));

      if (contextSchemas.length === 1) {
        // If there's only one schema in this context, use it
        schema = contextSchemas[0];
        schemaModule = schema.moduleName;
      } else if (contextSchemas.length > 1) {
        // Try to find one that ends with the simplified name
        if (simplifiedMatch) {
          const matchingSchema = contextSchemas.find(s => s.moduleName.endsWith('.' + simplifiedMatch[1]));
          if (matchingSchema) {
            schema = matchingSchema;
            schemaModule = schema.moduleName;
          }
        }
      }
    }
  }

  if (!schema) {
    return completions;
  }

  let fields = [];
  if (path.length === 0) {
    fields = schema.fields;
  } else {
    fields = schemaRegistry.getFieldsForPath(schemaModule, path);
  }

  fields.forEach((field, index) => {
    const item: CompletionItem = {
      label: field.name,
      kind: field.elixirType ? CompletionItemKind.Reference : CompletionItemKind.Field,
      detail: field.elixirType || `:${field.type}`,
      documentation: field.elixirType
        ? `Association: ${field.elixirType}`
        : `Field type: :${field.type}`,
      insertText: field.name,
      sortText: `!0${index.toString().padStart(3, '0')}`,
    };
    completions.push(item);
  });

  return completions;
}

/**
 * Build markdown documentation for an attribute
 */
function buildAttributeDocumentation(attr: ComponentAttribute): string {
  let doc = `**Attribute: \`${attr.name}\`**\n\n`;

  const typeDisplay = getAttributeTypeDisplay(attr);
  doc += `- **Type:** \`${typeDisplay}\`\n`;
  doc += `- **Required:** ${attr.required ? 'Yes' : 'No'}\n`;

  if (attr.default) {
    doc += `- **Default:** \`${attr.default}\`\n`;
  }

  if (attr.values && attr.values.length > 0) {
    doc += `- **Values:** ${attr.values.map(v => `\`:${v}\``).join(', ')}\n`;
  }

  if (attr.doc) {
    doc += `\n${attr.doc}\n`;
  }

  return doc;
}

function resolveSchemaFromAssignName(schemaRegistry: SchemaRegistry, assignName: string): string | null {
  if (!assignName) {
    return null;
  }

  const candidates = new Set<string>();
  candidates.add(toCamel(assignName));

  if (assignName.endsWith('s')) {
    const singular = assignName.slice(0, -1);
    if (singular.length > 0) {
      candidates.add(toCamel(singular));
    }
  }

  for (const candidate of candidates) {
    const resolved = schemaRegistry.resolveTypeName(candidate);
    if (resolved) {
      return resolved;
    }
  }

  return null;
}

function toCamel(value: string): string {
  return value
    .split('_')
    .filter(part => part.length > 0)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
