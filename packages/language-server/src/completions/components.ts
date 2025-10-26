import * as path from 'path';
import { CompletionItem, CompletionItemKind, InsertTextFormat, MarkupKind } from 'vscode-languageserver/node';
import {
  ComponentsRegistry,
  PhoenixComponent,
  ComponentAttribute,
  getAttributeTypeDisplay
} from '../components-registry';

/**
 * Get component name completions for local components (<.component_name>)
 */
export function getLocalComponentCompletions(
  componentsRegistry: ComponentsRegistry,
  templatePath: string
): CompletionItem[] {
  const { primary, secondary } = componentsRegistry.getComponentsForTemplate(templatePath);
  const completions: CompletionItem[] = [];

  // If no components found for this template, fallback to ALL components
  const allComponents = componentsRegistry.getAllComponents();

  if (primary.length === 0 && secondary.length === 0 && allComponents.length > 0) {
    // Fallback: show ALL components from registry
    allComponents.forEach((component, index) => {
      completions.push({
        label: component.name,
        kind: CompletionItemKind.Function,
        detail: `Component from ${component.moduleName}`,
        documentation: buildComponentDocumentation(component),
        insertText: `${component.name}>$1</.${component.name}>`,
        insertTextFormat: InsertTextFormat.Snippet,
        sortText: `!0${index.toString().padStart(3, '0')}`,
      });
    });
    return completions;
  }

  // Add primary components (from same module) with highest priority
  primary.forEach((component, index) => {
    completions.push({
      label: component.name,
      kind: CompletionItemKind.Function,
      detail: `Component from ${component.moduleName}`,
      documentation: buildComponentDocumentation(component),
      insertText: `${component.name}>$1</.${component.name}>`,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: `!0${index.toString().padStart(3, '0')}`,
    });
  });

  // Add secondary components (from other modules) with lower priority
  secondary.forEach((component, index) => {
    completions.push({
      label: component.name,
      kind: CompletionItemKind.Function,
      detail: `Component from ${component.moduleName}`,
      documentation: buildComponentDocumentation(component),
      insertText: `${component.name}>$1</.${component.name}>`,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: `!1${index.toString().padStart(3, '0')}`,
    });
  });

  return completions;
}

/**
 * Get component attribute completions for a specific component
 */
export function getComponentAttributeCompletions(
  component: PhoenixComponent
): CompletionItem[] {
  const completions: CompletionItem[] = [];

  component.attributes.forEach((attr, index) => {
    let insertText: string;
    const typeDisplay = getAttributeTypeDisplay(attr);
    let detail = `${typeDisplay}`;

    // Build detail string
    if (attr.required) {
      detail += ' (required)';
    } else if (attr.default) {
      detail += ` (default: ${attr.default})`;
    }

    // Build insert text based on type
    if (attr.name === 'module') {
      insertText = `${attr.name}={\${1:MyAppWeb.Component}}`;
    } else if (attr.name === 'navigate' || attr.name === 'patch') {
      insertText = `${attr.name}={~p"\${1:/path}"}`;
    } else if (attr.name === 'href') {
      insertText = `${attr.name}="\${1:/path}"`;
    } else if (attr.name === 'id') {
      insertText = `${attr.name}="\${1:component-id}"`;
    } else if (attr.type === 'boolean') {
      insertText = `${attr.name}`;
    } else if (attr.values && attr.values.length > 0) {
      // For enum types, provide snippet with choices
      insertText = `${attr.name}="\${1|${attr.values.join(',')}|}"`;
    } else if (attr.type === 'string') {
      insertText = `${attr.name}="$1"`;
    } else {
      insertText = `${attr.name}={$1}`;
    }

    completions.push({
      label: attr.name,
      kind: CompletionItemKind.Field,
      detail,
      documentation: attr.doc || `Attribute of type ${typeDisplay}`,
      insertText,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: attr.required
        ? `!0${index.toString().padStart(3, '0')}` // Required attrs first
        : `!1${index.toString().padStart(3, '0')}`,
    });
  });

  return completions;
}

/**
 * Get slot completions for a component usage (<:slot_name>)
 */
export function getComponentSlotCompletions(
  component: PhoenixComponent
): CompletionItem[] {
  const completions: CompletionItem[] = [];

  component.slots.forEach((slot, index) => {
    // Don't suggest inner_block - it's implicit
    if (slot.name === 'inner_block') {
      return;
    }

    // Build rich markdown documentation
    let doc = `**Slot for \`<.${component.name}>\`**\n\n`;

    if (slot.required) {
      doc += '**Required** ';
    } else {
      doc += '**Optional** ';
    }
    doc += '\n\n';

    if (slot.doc) {
      doc += slot.doc + '\n\n';
    }

    // Show slot attributes if any
    if (slot.attributes && slot.attributes.length > 0) {
      doc += '**Slot Attributes:**\n';
      slot.attributes.forEach(attr => {
        doc += `- \`${attr.name}\`: \`:${attr.type}\``;
        if (attr.required) {
          doc += ' **(required)**';
        }
        if (attr.default) {
          doc += ` (default: \`${attr.default}\`)`;
        }
        if (attr.doc) {
          doc += `\n  ${attr.doc}`;
        }
        doc += '\n';
      });
      doc += '\n';
    }

    // Example usage
    doc += '**Example:**\n```heex\n';
    if (slot.attributes && slot.attributes.length > 0) {
      const attrExample = slot.attributes
        .filter(a => a.required)
        .map(a => `${a.name}="${a.name}"`)
        .join(' ');
      doc += `<:${slot.name}${attrExample ? ' ' + attrExample : ''}>\n  Slot content\n</:${slot.name}>\n`;
    } else {
      doc += `<:${slot.name}>\n  Slot content\n</:${slot.name}>\n`;
    }
    doc += '```';

    // Build insert text with slot attributes as placeholders
    let insertText = `${slot.name}`;
    let placeholderIndex = 1;

    // Add required attributes as snippet placeholders
    if (slot.attributes && slot.attributes.length > 0) {
      const requiredAttrs = slot.attributes.filter(a => a.required);
      if (requiredAttrs.length > 0) {
        insertText += ' ';
        requiredAttrs.forEach((attr, i) => {
          insertText += `${attr.name}=\${${placeholderIndex++}:${attr.name}}`;
          if (i < requiredAttrs.length - 1) {
            insertText += ' ';
          }
        });
      }
    }

    insertText += `>\n  \${${placeholderIndex}:content}\n</:${slot.name}>`;

    completions.push({
      label: `:${slot.name}`,
      kind: CompletionItemKind.Property,
      detail: `Slot${slot.required ? ' (required)' : ''}`,
      documentation: {
        kind: MarkupKind.Markdown,
        value: doc,
      },
      insertText: insertText,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: slot.required
        ? `!0${index.toString().padStart(3, '0')}`
        : `!1${index.toString().padStart(3, '0')}`,
      filterText: `:${slot.name}`,
    });
  });

  return completions;
}

/**
 * Get remote component completions (Module.component_name)
 */
export function getRemoteComponentCompletions(
  componentsRegistry: ComponentsRegistry,
  moduleName: string
): CompletionItem[] {
  const components = componentsRegistry.getComponentsFromModule(moduleName);
  const completions: CompletionItem[] = [];

  components.forEach((component, index) => {
    completions.push({
      label: component.name,
      kind: CompletionItemKind.Function,
      detail: `Component from ${component.moduleName}`,
      documentation: buildComponentDocumentation(component),
      insertText: `${component.name}>$1</.${component.name}>`,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: `!0${index.toString().padStart(3, '0')}`,
    });
  });

  return completions;
}

/**
 * Check if cursor is in a local component tag context (<.component_name)
 */
export function isLocalComponentContext(linePrefix: string): boolean {
  // Match: <. followed by optional component name
  return /<\.([a-z_][a-z0-9_]*)?$/.test(linePrefix);
}

/**
 * Check if cursor is in a remote component context (<Module.component_name)
 */
export function isRemoteComponentContext(linePrefix: string): { match: boolean; module?: string } {
  // Match: <ModuleName. or <Module.SubModule.
  const match = /<([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.([a-z_][a-z0-9_]*)?$/.exec(linePrefix);

  if (match) {
    return {
      match: true,
      module: match[1],
    };
  }

  return { match: false };
}

/**
 * Check if cursor is inside a component tag for attribute completions
 * Returns component name if found
 */
export function getComponentNameFromContext(linePrefix: string): string | null {
  // Match local component: <.component_name attributes...
  const localMatch = /<\.([a-z_][a-z0-9_]*)\s+[^>]*$/.exec(linePrefix);
  if (localMatch) {
    return localMatch[1];
  }

  // Match remote component: <Module.component_name attributes...
  const remoteMatch = /<[A-Z][a-zA-Z0-9.]*\.([a-z_][a-z0-9_]*)\s+[^>]*$/.exec(linePrefix);
  if (remoteMatch) {
    return remoteMatch[1];
  }

  return null;
}

/**
 * Get module name from remote component context
 */
export function getModuleNameFromContext(linePrefix: string): string | null {
  // Match: <Module.component_name or <Module.SubModule.component_name
  const match = /<([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9])*)\.[a-z_][a-z0-9_]*\s+[^>]*$/.exec(linePrefix);

  if (match) {
    return match[1];
  }

  return null;
}

/**
 * Build comprehensive component documentation
 */
function buildComponentDocumentation(component: PhoenixComponent): string {
  let doc = '';

  // Add component description
  if (component.doc) {
    doc += `${component.doc}\n\n`;
  }

  // Add attributes section
  if (component.attributes.length > 0) {
    doc += '**Attributes:**\n';
    component.attributes.forEach(attr => {
      const required = attr.required ? ' (required)' : '';
      const defaultValue = attr.default ? ` = ${attr.default}` : '';
      const values = attr.values ? ` ∈ {${attr.values.join(', ')}}` : '';
      const typeDisplay = getAttributeTypeDisplay(attr);
      doc += `- \`${attr.name}\`: ${typeDisplay}${required}${defaultValue}${values}\n`;
      if (attr.doc) {
        doc += `  ${attr.doc}\n`;
      }
    });
    doc += '\n';
  }

  // Add slots section
  if (component.slots.length > 0) {
    doc += '**Slots:**\n';
    component.slots.forEach(slot => {
      const required = slot.required ? ' (required)' : '';
      doc += `- \`${slot.name}\`${required}\n`;
      if (slot.doc) {
        doc += `  ${slot.doc}\n`;
      }
    });
    doc += '\n';
  }

  // Add usage example
  doc += `**Module:** \`${component.moduleName}\`\n`;
  doc += `**File:** \`${path.basename(component.filePath)}\` (line ${component.line})`;

  return doc;
}

/**
 * Get all available module names (for remote component completion)
 */
export function getAvailableModules(componentsRegistry: ComponentsRegistry): string[] {
  const modules = new Set<string>();
  const allComponents = componentsRegistry.getAllComponents();

  allComponents.forEach(component => {
    modules.add(component.moduleName);
  });

  return Array.from(modules).sort();
}

/**
 * Build hover documentation for component
 */
export function buildComponentHoverDocumentation(component: PhoenixComponent): string {
  let doc = `**Component: \`<.${component.name}>\`**\n\n`;

  if (component.doc) {
    doc += `${component.doc}\n\n`;
  }

  doc += `**Module:** \`${component.moduleName}\`\n`;
  doc += `**File:** \`${path.basename(component.filePath)}\` (line ${component.line})\n\n`;

  // Attributes
  if (component.attributes.length > 0) {
    doc += '**Attributes:**\n\n';
    component.attributes.forEach(attr => {
      const required = attr.required ? '**required**' : 'optional';
      const defaultValue = attr.default ? ` (default: \`${attr.default}\`)` : '';
      const typeDisplay = getAttributeTypeDisplay(attr);
      doc += `- \`${attr.name}\`: \`${typeDisplay}\` - ${required}${defaultValue}\n`;

      if (attr.values && attr.values.length > 0) {
        doc += `  - Values: ${attr.values.map(v => `\`"${v}"\``).join(', ')}\n`;
      }

      if (attr.doc) {
        doc += `  - ${attr.doc}\n`;
      }
    });
    doc += '\n';
  }

  // Slots
  if (component.slots.length > 0) {
    doc += '**Slots:**\n\n';
    component.slots.forEach(slot => {
      const required = slot.required ? '**required**' : 'optional';
      doc += `- \`<:${slot.name}>\` - ${required}\n`;
      if (slot.doc) {
        doc += `  - ${slot.doc}\n`;
      }
    });
    doc += '\n';
  }

  // Example usage
  doc += '**Example:**\n\n```heex\n';
  doc += `<.${component.name}`;

  // Add required attributes to example
  const requiredAttrs = component.attributes.filter(a => a.required);
  if (requiredAttrs.length > 0) {
    doc += '\n';
    requiredAttrs.forEach(attr => {
      if (attr.type === 'boolean') {
        doc += `  ${attr.name}\n`;
      } else if (attr.values && attr.values.length > 0) {
        doc += `  ${attr.name}="${attr.values[0]}"\n`;
      } else if (attr.type === 'string') {
        doc += `  ${attr.name}="..."\n`;
      } else {
        doc += `  ${attr.name}={...}\n`;
      }
    });
    doc += '/>\n';
  } else {
    doc += ' />\n';
  }

  doc += '```';

  return doc;
}

/**
 * Build hover documentation for component attribute
 */
export function buildAttributeHoverDocumentation(
  component: PhoenixComponent,
  attributeName: string
): string | null {
  const attr = component.attributes.find(a => a.name === attributeName);

  if (!attr) {
    return null;
  }

  let doc = `**Attribute: \`${attr.name}\`**\n\n`;

  const typeDisplay = getAttributeTypeDisplay(attr);
  doc += `**Type:** \`${typeDisplay}\`\n`;
  doc += `**Required:** ${attr.required ? 'Yes' : 'No'}\n`;

  if (attr.default) {
    doc += `**Default:** \`${attr.default}\`\n`;
  }

  if (attr.values && attr.values.length > 0) {
    doc += `**Allowed values:** ${attr.values.map(v => `\`"${v}"\``).join(', ')}\n`;
  }

  if (attr.doc) {
    doc += `\n${attr.doc}\n`;
  }

  doc += `\n---\n\n`;
  doc += `From component: \`<.${component.name}>\``;

  return doc;
}
