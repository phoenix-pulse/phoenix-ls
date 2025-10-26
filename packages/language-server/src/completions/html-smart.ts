import { CompletionItem, CompletionItemKind, InsertTextFormat } from 'vscode-languageserver/node';
import { getAttributesFor, AttributeData } from './html-attributes-data';

/**
 * Extract element name from line prefix
 * Example: "<img src="..." █" → returns "img"
 * Example: "<div class="..." █" → returns "div"
 */
function getElementFromContext(linePrefix: string): string | null {
  // Match: <tagname ...attributes...
  // This regex matches HTML opening tags with attributes being typed
  const match = linePrefix.match(/<([a-z][a-z0-9]*)\s+[^>]*$/i);
  return match ? match[1].toLowerCase() : null;
}

/**
 * Create completion item from attribute data
 * Converts our attribute data structure into LSP CompletionItem format
 */
function createAttributeCompletion(
  attr: AttributeData,
  index: number
): CompletionItem {
  // Determine insert text based on attribute type
  let insertText: string;

  if (attr.snippet) {
    // Custom snippet (e.g., data-* = data-${1:name}="${2:value}")
    insertText = attr.snippet;
  } else if (attr.boolean) {
    // Boolean attribute (e.g., hidden, disabled, required)
    // Just insert attribute name, no ="value"
    insertText = attr.name;
  } else if (attr.values.length > 0) {
    // Has predefined values - create choice snippet
    // Example: type="${1|text,email,password|}"
    const valuesStr = attr.values.join(',');
    insertText = `${attr.name}="\${1|${valuesStr}|}"`;
  } else {
    // Free-form value
    // Example: name="${1:value}"
    insertText = `${attr.name}="\${1:value}"`;
  }

  // Prioritize commonly used attributes
  // Common attrs appear higher in completion list
  const commonAttrs = [
    'id', 'class', 'style',        // Universal styling
    'type', 'name', 'value',       // Forms
    'href', 'src', 'alt',          // Links & media
    'placeholder', 'required',     // Form UX
  ];
  const sortPrefix = commonAttrs.includes(attr.name) ? '!6' : '!7';

  return {
    label: attr.name,
    kind: CompletionItemKind.Property,
    detail: attr.doc,
    documentation: attr.doc,
    insertText,
    insertTextFormat: InsertTextFormat.Snippet,
    sortText: `${sortPrefix}${index.toString().padStart(3, '0')}`,
  };
}

/**
 * Detect if cursor is inside HTML attribute value quotes
 * Example: <input type="█"> → returns { element: "input", attribute: "type", partialValue: "" }
 * Example: <input type="em█"> → returns { element: "input", attribute: "type", partialValue: "em" }
 */
function getAttributeValueContext(linePrefix: string): {
  element: string;
  attribute: string;
  partialValue: string;
} | null {
  // Pattern: <element ...attributes... attr="partial█"
  // Matches both double and single quotes
  const valuePattern = /<([a-z][a-z0-9]*)\s+[^>]*?(\w+)=["']([^"']*)$/i;
  const match = linePrefix.match(valuePattern);

  if (!match) {
    return null;
  }

  return {
    element: match[1].toLowerCase(),
    attribute: match[2].toLowerCase(),
    partialValue: match[3],
  };
}

/**
 * Get HTML attribute value completions
 *
 * Provides value suggestions when cursor is inside attribute quotes.
 * Example: <input type="█"> → returns ["text", "email", "password", ...]
 *
 * @param linePrefix - Text from start of line to cursor position
 * @returns Array of value completion items
 */
export function getHtmlAttributeValueCompletions(linePrefix: string): CompletionItem[] {
  // Check if cursor is inside attribute value quotes
  const context = getAttributeValueContext(linePrefix);

  if (!context) {
    return [];
  }

  // Get all attributes for this element
  const attrs = getAttributesFor(context.element);

  // Find the specific attribute being edited
  const attr = attrs.find(a => a.name === context.attribute);

  // If attribute doesn't have predefined values, return empty
  if (!attr || attr.values.length === 0) {
    return [];
  }

  // Create completion items for each value
  return attr.values.map((value, index) => ({
    label: value,
    kind: CompletionItemKind.Value,
    detail: `${context.attribute} value for <${context.element}>`,
    documentation: attr.doc,
    insertText: value,
    filterText: value,
    sortText: `!0${index.toString().padStart(3, '0')}`, // High priority
  }));
}

/**
 * Get smart, context-aware HTML attribute completions
 *
 * This function provides intelligent HTML attribute suggestions based on the
 * element being edited. For example:
 * - <img █> shows src, alt, width, height, loading, etc.
 * - <input █> shows type, name, value, placeholder, required, etc.
 * - <div █> shows only global attrs (id, class, style, etc.)
 *
 * @param linePrefix - Text from start of line to cursor position
 * @returns Array of completion items sorted by relevance
 */
export function getSmartHtmlCompletions(linePrefix: string): CompletionItem[] {
  // Extract element name from context (e.g., "img" from "<img src=...")
  const element = getElementFromContext(linePrefix);

  // Get attributes for this specific element
  // Returns: element-specific + global + ARIA attributes
  const attrs = getAttributesFor(element);

  // Convert attribute data to completion items
  return attrs.map((attr, index) => createAttributeCompletion(attr, index));
}
