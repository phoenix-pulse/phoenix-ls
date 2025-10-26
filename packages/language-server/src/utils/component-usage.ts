import { TextDocument } from 'vscode-languageserver-textdocument';
import { Range } from 'vscode-languageserver/node';
import { getHeexTree, isTreeSitterReady } from '../parsers/tree-sitter';
import type { SyntaxNode } from '../parsers/tree-sitter-types';
import { parseHEExFile, parseHEExContent, isHEExMetadata, type HEExComponentUsage } from '../parsers/elixir-ast-parser';

export interface AttributeUsage {
  name: string;
  start: number;
  end: number;
  valueStart?: number;
  valueEnd?: number;
  valueText?: string;
}

export interface ComponentUsage {
  componentName: string;
  moduleContext?: string;
  isLocal: boolean;
  openTagStart: number;
  openTagEnd: number;
  nameStart: number;
  nameEnd: number;
  attributesStart: number;
  attributesEnd: number;
  attributes: AttributeUsage[];
  selfClosing: boolean;
  contentStart?: number;
  contentEnd?: number;
  blockEnd: number;
  slots: SlotUsage[];
  providedSlotNames?: Set<string>;
}

export interface SlotUsage {
  name: string;
  start: number;
  end: number;
  selfClosing: boolean;
  attributes: AttributeUsage[]; // Attributes on the slot tag (e.g., <:item title="foo">)
}

export const SPECIAL_TEMPLATE_ATTRIBUTES = new Set([':for', ':if', ':let', ':key']);

const KNOWN_HTML_ATTRIBUTES = new Set([
  'id',
  'class',
  'style',
  'title',
  'type',
  'value',
  'name',
  'disabled',
  'checked',
  'selected',
  'placeholder',
  'href',
  'src',
  'alt',
  'width',
  'height',
  'target',
  'rel',
  'method',
  'action',
  'role',
  'tabindex',
  'autocomplete',
  'autofocus',
  'required',
  'draggable',
  'download',
  'maxlength',
  'minlength',
  'rows',
  'cols',
  'wrap',
  'accept',
  'multiple',
  'pattern',
  'step',
  'max',
  'min',
  'readonly',
  'form',
  'for',
  'enctype',
  'novalidate',
  'spellcheck',
  'contenteditable',
  'referrerpolicy',
  'sizes',
  'srcset',
  'loading',
  'decoding',
  'poster',
  'controls',
  'loop',
  'muted',
  'playsinline',
  'preload',
  'datetime',
  'lang',
  'data',
  'cols',
  'rows',
]);

interface TreeComponentMatch {
  componentName: string;
  moduleContext?: string;
  isLocal: boolean;
}

function parseComponentTagName(tagName: string): TreeComponentMatch | null {
  if (!tagName) {
    return null;
  }

  if (tagName.startsWith('.')) {
    const componentName = tagName.slice(1);
    if (/^[a-z_][a-z0-9_]*$/i.test(componentName)) {
      return {
        componentName,
        isLocal: true,
      };
    }
    return null;
  }

  if (tagName.includes('.')) {
    const lastDot = tagName.lastIndexOf('.');
    const moduleContext = tagName.slice(0, lastDot);
    const componentName = tagName.slice(lastDot + 1);
    if (
      moduleContext.length > 0 &&
      componentName.length > 0 &&
      /^[A-Z]/.test(moduleContext) &&
      /^[a-z_][a-z0-9_]*$/i.test(componentName)
    ) {
      return {
        componentName,
        moduleContext,
        isLocal: false,
      };
    }
  }

  return null;
}

function getNodeText(node: SyntaxNode, source: string): string {
  return source.slice(node.startIndex, node.endIndex);
}

function findDescendantByType(node: SyntaxNode | null, type: string): SyntaxNode | null {
  if (!node || typeof node.type !== 'string') {
    return null;
  }
  if (node.type === type) {
    return node;
  }
  const children = node.namedChildren ?? node.children ?? [];
  for (const child of children) {
    const found = findDescendantByType(child, type);
    if (found) {
      return found;
    }
  }
  return null;
}

function collectUsagesFromTree(text: string, cacheKey: string): ComponentUsage[] | null {
  try {
    const tree = getHeexTree(cacheKey, text);
    if (!tree) {
      return null;
    }

    const usages: ComponentUsage[] = [];
    const visit = (node: SyntaxNode) => {
      if (!node || typeof node.type !== 'string') {
        return;
      }

      if (node.type === 'element' || node.type === 'component' || node.type === 'component_block') {
        const openTag =
          node.childForFieldName('start_tag') ??
          node.childForFieldName('open_tag') ??
          node.childForFieldName('start_component') ??
          node.childForFieldName('open_component') ??
          node.namedChildren.find(
            (child) =>
              child.type === 'start_tag' ||
              child.type === 'open_tag' ||
              child.type === 'start_component' ||
              child.type === 'open_component'
          );
        if (!openTag) {
          node.namedChildren?.forEach(visit);
          return;
        }

        const tagNameNode =
          openTag.childForFieldName('name') ??
          openTag.childForFieldName('tag_name') ??
          openTag.namedChildren.find((child) => child.type === 'tag_name' || child.type === 'component_name');

        const tagNameText = tagNameNode ? getNodeText(tagNameNode, text) : '';
        const componentMatch = parseComponentTagName(tagNameText);
        if (!componentMatch) {
          node.namedChildren.forEach(visit);
          return;
        }

        const closeTag =
          node.childForFieldName('end_tag') ??
          node.childForFieldName('close_tag') ??
          node.childForFieldName('end_component') ??
          node.childForFieldName('close_component') ??
          node.namedChildren.find((child) =>
            child.type === 'end_tag' ||
            child.type === 'close_tag' ||
            child.type === 'end_component' ||
            child.type === 'close_component'
          );

        const attributes: AttributeUsage[] = [];
        const attributeNodes = openTag.namedChildren.filter((child) => child.type === 'attribute');
        for (const attrNode of attributeNodes) {
          const nameNode = attrNode.childForFieldName('name') ?? attrNode.namedChildren.find((child) => child.type === 'attribute_name');
          if (!nameNode) {
            continue;
          }

          const nameText = getNodeText(nameNode, text);
          const attr: AttributeUsage = {
            name: nameText,
            start: nameNode.startIndex,
            end: nameNode.endIndex,
          };

          const valueNode = attrNode.childForFieldName('value') ?? attrNode.namedChildren.find((child) => child.type.includes('value'));
          if (valueNode) {
            attr.valueStart = valueNode.startIndex;
            attr.valueEnd = valueNode.endIndex;
            attr.valueText = getNodeText(valueNode, text);
          }

          attributes.push(attr);
        }

        const slots: SlotUsage[] = [];
        const slotNodes = node.namedChildren.filter((child) => child.type === 'slot' || child.type === 'self_closing_slot');

        slotNodes.forEach((slotNode) => {
          const slotNameNode = findDescendantByType(slotNode, 'slot_name');
          const slotName = slotNameNode ? getNodeText(slotNameNode, text) : null;
          if (slotName) {
            // Extract attributes from slot tag (e.g., <:item title="foo">)
            const slotAttributes: AttributeUsage[] = [];
            const slotOpenTag = slotNode.childForFieldName('start_slot') ??
                                 slotNode.childForFieldName('open_slot') ??
                                 slotNode.namedChildren.find(child => child.type === 'start_slot' || child.type === 'open_slot');

            if (slotOpenTag) {
              const slotAttrNodes = slotOpenTag.namedChildren.filter((child) => child.type === 'attribute');
              for (const attrNode of slotAttrNodes) {
                const nameNode = attrNode.childForFieldName('name') ?? attrNode.namedChildren.find((child) => child.type === 'attribute_name');
                if (!nameNode) continue;

                const nameText = getNodeText(nameNode, text);
                const attr: AttributeUsage = {
                  name: nameText,
                  start: nameNode.startIndex,
                  end: nameNode.endIndex,
                };

                const valueNode = attrNode.childForFieldName('value') ?? attrNode.namedChildren.find((child) => child.type.includes('value'));
                if (valueNode) {
                  attr.valueStart = valueNode.startIndex;
                  attr.valueEnd = valueNode.endIndex;
                  attr.valueText = getNodeText(valueNode, text);
                }

                slotAttributes.push(attr);
              }
            }

            slots.push({
              name: slotName,
              start: slotNode.startIndex,
              end: slotNode.endIndex,
              selfClosing: slotNode.type === 'self_closing_slot',
              attributes: slotAttributes,
            });
          }
        });

        const providedSlotNames = new Set<string>();
        const selfClosing = !closeTag;
        const componentUsage: ComponentUsage = {
          componentName: componentMatch.componentName,
          moduleContext: componentMatch.moduleContext,
          isLocal: componentMatch.isLocal,
          openTagStart: openTag.startIndex,
          openTagEnd: openTag.endIndex,
          nameStart: tagNameNode ? tagNameNode.startIndex : openTag.startIndex,
          nameEnd: tagNameNode ? tagNameNode.endIndex : openTag.endIndex,
          attributesStart: openTag.startIndex,
          attributesEnd: openTag.endIndex,
          attributes,
          selfClosing,
          blockEnd: node.endIndex,
          slots,
          providedSlotNames,
        };

        if (!selfClosing && closeTag) {
          componentUsage.contentStart = openTag.endIndex;
          componentUsage.contentEnd = closeTag.startIndex;
        }

        slots.forEach(slot => providedSlotNames.add(slot.name));

        usages.push(componentUsage);
      }

      const children = node.namedChildren ?? [];
      for (const child of children) {
        visit(child);
      }
    };

    visit(tree.rootNode);
    usages.sort((a, b) => a.openTagStart - b.openTagStart);
    return usages;
  } catch (error) {
    if (process.env.PHOENIX_LSP_DEBUG_TREE_SITTER === '1') {
      console.log(`[TreeSitter] Unable to derive component usages from tree: ${error}`);
    }
    return null;
  }
}

export function collectComponentUsages(text: string, cacheKey = '__anonymous__'): ComponentUsage[] {
  if (isTreeSitterReady()) {
    const treeBased = collectUsagesFromTree(text, cacheKey);
    if (treeBased) {
      return treeBased;
    }
  }

  const usages: ComponentUsage[] = [];
  usages.push(...collectUsages(text, /<\.([a-z_][a-z0-9_]*)\b/g, true));
  usages.push(...collectUsages(text, /<([A-Z][\w]*(?:\.[A-Z][\w]*)*)\.([a-z_][a-z0-9_]*)\b/g, false));
  usages.sort((a, b) => a.openTagStart - b.openTagStart);
  return usages;
}

/**
 * Async version of collectComponentUsages that uses Elixir HEEx parser.
 * Falls back to tree-sitter or regex if Elixir parser unavailable.
 *
 * @param text - HEEx template text
 * @param filePath - Optional file path for Elixir parser (if not provided, falls back to regex)
 * @param cacheKey - Cache key for tree-sitter/regex fallback
 * @returns Promise of component usages
 */
export async function collectComponentUsagesAsync(
  text: string,
  filePath?: string,
  cacheKey = '__anonymous__'
): Promise<ComponentUsage[]> {
  console.log('[collectComponentUsagesAsync] Called with filePath:', filePath);

  // Try Elixir parser first (most accurate, handles nesting correctly)
  if (filePath) {
    const isHeexFile = filePath.endsWith('.heex');
    const isElixirFile = filePath.endsWith('.ex') || filePath.endsWith('.exs');

    console.log('[collectComponentUsagesAsync] File type:', { isHeexFile, isElixirFile });

    if (isHeexFile || isElixirFile) {
      try {
        let result;

        if (isHeexFile) {
          // For .heex files: Use file-based parsing (with caching)
          console.log('[collectComponentUsagesAsync] Using parseHEExFile (file-based)');
          result = await parseHEExFile(filePath);
        } else {
          // For .ex/.exs files: Parse text content directly (HEEx in ~H sigils)
          console.log('[collectComponentUsagesAsync] Using parseHEExContent (content-based)');
          result = await parseHEExContent(text, filePath);
        }

        console.log('[collectComponentUsagesAsync] Parse result:', JSON.stringify(result).substring(0, 200));

        if (isHEExMetadata(result)) {
          console.log('[collectComponentUsagesAsync] ✅ Success! Using Elixir HEEx parser');
          console.log('[collectComponentUsagesAsync] Found', result.components.length, 'components');
          // Convert Elixir parser result to ComponentUsage format
          return result.components.map((comp: HEExComponentUsage) => convertHEExComponent(comp, text));
        } else {
          console.log('[collectComponentUsagesAsync] ❌ Result is error:', result);
        }
      } catch (error) {
        console.log('[collectComponentUsagesAsync] ❌ Exception:', error);
        console.log('[collectComponentUsagesAsync] Stack:', error instanceof Error ? error.stack : 'No stack');
      }
    } else {
      console.log('[collectComponentUsagesAsync] Not a HEEx-related file, skipping Elixir parser');
    }
  } else {
    console.log('[collectComponentUsagesAsync] No filePath provided, skipping Elixir parser');
  }

  // Fallback to sync version (tree-sitter or regex)
  console.log('[collectComponentUsagesAsync] Using tree-sitter/regex fallback');
  return collectComponentUsages(text, cacheKey);
}

/**
 * Convert Elixir HEEx parser result to ComponentUsage format
 */
function convertHEExComponent(heexComp: HEExComponentUsage, text: string): ComponentUsage {
  // Find attributes start/end (simplified for now - between name_end and first >)
  const afterName = text.indexOf('>', heexComp.name_end);
  const attributesStart = heexComp.name_end;
  const attributesEnd = afterName !== -1 ? afterName : heexComp.name_end;

  // Calculate content range for non-self-closing components
  let contentStart: number | undefined;
  let contentEnd: number | undefined;

  if (!heexComp.self_closing) {
    // Content is between opening tag end and closing tag start
    const openTagEnd = text.indexOf('>', heexComp.start_offset);
    if (openTagEnd !== -1) {
      contentStart = openTagEnd + 1;
      // Find closing tag (simplified - could be improved)
      const closingPattern = heexComp.is_local
        ? `</.${heexComp.name}>`
        : `</${heexComp.module_context}.${heexComp.name}>`;
      const closingTagStart = text.indexOf(closingPattern, contentStart);
      if (closingTagStart !== -1) {
        contentEnd = closingTagStart;
      }
    }
  }

  // Convert slots
  const slots: SlotUsage[] = heexComp.slots.map(slot => ({
    name: slot.name,
    start: slot.start_offset,
    end: slot.end_offset,
    selfClosing: slot.self_closing,
    attributes: []  // Attributes not yet parsed in Elixir parser
  }));

  return {
    componentName: heexComp.name,
    moduleContext: heexComp.module_context || undefined,
    isLocal: heexComp.is_local,
    openTagStart: heexComp.start_offset,
    openTagEnd: attributesEnd,
    nameStart: heexComp.name_start,
    nameEnd: heexComp.name_end,
    attributesStart,
    attributesEnd,
    attributes: [],  // Attributes not yet parsed in Elixir parser
    selfClosing: heexComp.self_closing,
    contentStart,
    contentEnd,
    blockEnd: heexComp.end_offset,
    slots,
    providedSlotNames: new Set(slots.map(s => s.name))
  };
}

export function shouldIgnoreUnknownAttribute(name: string): boolean {
  if (SPECIAL_TEMPLATE_ATTRIBUTES.has(name)) {
    return true;
  }
  // Special case: {@rest} spread operator for global attributes
  // Can appear as "rest" or "@rest" depending on how it's parsed
  if (name === 'rest' || name === '@rest') {
    return true;
  }
  if (name.startsWith('phx-') || name.startsWith('data-') || name.startsWith('aria-')) {
    return true;
  }
  if (name.startsWith('on-')) {
    return true;
  }
  if (KNOWN_HTML_ATTRIBUTES.has(name)) {
    return true;
  }
  return false;
}

export function createRange(document: TextDocument, start: number, end: number): Range {
  return {
    start: document.positionAt(start),
    end: document.positionAt(end),
  };
}

export function isSlotProvided(slotName: string, usage: ComponentUsage, text: string): boolean {
  if (usage.selfClosing || usage.contentStart == null || usage.contentEnd == null) {
    return false;
  }

  if (usage.providedSlotNames && usage.providedSlotNames.has(slotName)) {
    return true;
  }

  if (isTreeSitterReady()) {
    if (slotName === 'inner_block') {
      const content = text.slice(usage.contentStart, usage.contentEnd);
      return content.trim().length > 0;
    }
    return usage.slots.some(slot => slot.name === slotName);
  }

  const content = text.slice(usage.contentStart, usage.contentEnd);

  if (slotName === 'inner_block') {
    return content.trim().length > 0;
  }

  const slotTagPattern = new RegExp(`<:${slotName}\\b`);
  if (slotTagPattern.test(content)) {
    return true;
  }

  const renderSlotPattern = new RegExp(`render_slot\\(\\s*@${slotName}`);
  if (renderSlotPattern.test(content)) {
    return true;
  }

  return false;
}

function collectUsages(text: string, pattern: RegExp, isLocal: boolean): ComponentUsage[] {
  const usages: ComponentUsage[] = [];
  pattern.lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    const openTagStart = match.index;
    const componentName = isLocal ? match[1] : match[2];
    const moduleContext = isLocal ? undefined : match[1];
    const matchText = match[0];
    const rawAttrStart = openTagStart + matchText.length;

    const tagEnd = findTagEnd(text, rawAttrStart);
    if (tagEnd === -1) {
      pattern.lastIndex = openTagStart + 1;
      continue;
    }

    let attrEnd = tagEnd;
    let cursor = tagEnd - 1;
    while (cursor >= rawAttrStart && /\s/.test(text[cursor])) {
      cursor--;
    }
    const selfClosing = cursor >= rawAttrStart && text[cursor] === '/';
    if (selfClosing) {
      attrEnd = cursor;
    }

    const attributes = parseAttributes(text.slice(rawAttrStart, attrEnd), rawAttrStart);

    let contentStart: number | undefined;
    let contentEnd: number | undefined;
    let blockEnd = tagEnd + 1;
    if (!selfClosing) {
      const closing = findMatchingClosingTag(
        text,
        tagEnd + 1,
        componentName,
        moduleContext,
        isLocal
      );
      if (closing) {
        contentStart = tagEnd + 1;
        contentEnd = closing.closeStart;
        blockEnd = closing.closeEnd;
      }
    }

    const nameStart = isLocal
      ? openTagStart + 2
      : openTagStart + 1 + (moduleContext ? moduleContext.length : 0) + 1;
    const nameEnd = nameStart + componentName.length;

    const slots: SlotUsage[] = [];
    if (contentStart != null && contentEnd != null) {
      // Find nested component ranges to exclude their slots
      const nestedComponentRanges = findNestedComponentRanges(text, contentStart, contentEnd);

      const slotRegex = /<:([a-z_][a-z0-9_-]*)/g;
      let slotMatch: RegExpExecArray | null;
      const contentSlice = text.slice(contentStart, contentEnd);
      while ((slotMatch = slotRegex.exec(contentSlice)) !== null) {
        const name = slotMatch[1];
        const tagStart = contentStart + slotMatch.index;

        // Skip slots that are inside nested components
        const isInsideNestedComponent = nestedComponentRanges.some(range =>
          tagStart >= range.start && tagStart < range.end
        );
        if (isInsideNestedComponent) {
          continue;
        }

        const closingIndex = contentSlice.indexOf('>', slotMatch.index);
        const absoluteEnd = closingIndex === -1 ? tagStart + name.length + 2 : contentStart + closingIndex + 1;
        const beforeClose = closingIndex === -1 ? '' : contentSlice.slice(slotMatch.index, closingIndex);
        const selfClosingSlot = /\/\s*$/.test(beforeClose.trim());

        // Parse slot attributes (e.g., <:item title="foo" description="bar">)
        const slotAttributes: AttributeUsage[] = [];
        if (closingIndex !== -1) {
          // Extract text between slot name and closing >
          // Match text: "<:item title="foo">" → extract " title="foo""
          const afterNameIndex = slotMatch.index + slotMatch[0].length; // After "<:item"
          const beforeCloseIndex = closingIndex;
          const attrText = contentSlice.slice(afterNameIndex, beforeCloseIndex);

          // Remove trailing "/" if self-closing
          const cleanAttrText = attrText.replace(/\/\s*$/, '').trim();
          if (cleanAttrText.length > 0) {
            const attrStartOffset = contentStart + afterNameIndex;
            const parsedAttrs = parseAttributes(cleanAttrText, attrStartOffset);
            slotAttributes.push(...parsedAttrs);
          }
        }

        slots.push({
          name,
          start: tagStart,
          end: absoluteEnd,
          selfClosing: selfClosingSlot,
          attributes: slotAttributes,
        });
      }
    }

    const providedSlotNames = new Set<string>();
    slots.forEach(slot => providedSlotNames.add(slot.name));

    usages.push({
      componentName,
      moduleContext,
      isLocal,
      openTagStart,
      openTagEnd: tagEnd + 1,
      nameStart,
      nameEnd,
      attributesStart: rawAttrStart,
      attributesEnd: attrEnd,
      attributes,
      selfClosing,
      contentStart,
      contentEnd,
      blockEnd,
      slots,
      providedSlotNames,
    });

    pattern.lastIndex = tagEnd + 1;
  }

  return usages;
}

function parseAttributes(text: string, baseOffset: number): AttributeUsage[] {
  const attributes: AttributeUsage[] = [];
  const length = text.length;
  let i = 0;

  // Safety limit to prevent infinite loops on malformed input
  // Allow up to 500 iterations (should be more than enough for any valid component)
  const MAX_ITERATIONS = 500;
  let iterations = 0;

  while (i < length && iterations < MAX_ITERATIONS) {
    iterations++;
    while (i < length && /\s/.test(text[i])) {
      i++;
    }
    if (i >= length) {
      break;
    }
    if (text[i] === '/') {
      break;
    }

    const nameStartIndex = i;
    while (i < length && /[A-Za-z0-9_.:-]/.test(text[i])) {
      i++;
    }

    if (nameStartIndex === i) {
      i++;
      continue;
    }

    const name = text.slice(nameStartIndex, i);
    const attrStart = baseOffset + nameStartIndex;
    const attrEnd = baseOffset + i;
    const attr: AttributeUsage = {
      name,
      start: attrStart,
      end: attrEnd,
    };
    attributes.push(attr);

    while (i < length && /\s/.test(text[i])) {
      i++;
    }

    if (i < length && text[i] === '=') {
      i++;
      while (i < length && /\s/.test(text[i])) {
        i++;
      }
      if (i >= length) {
        break;
      }

      const valueStartIndex = i;
      const ch = text[i];

      if (ch === '"' || ch === '\'') {
        const quote = ch;
        i++;
        while (i < length) {
          if (text[i] === quote && text[i - 1] !== '\\') {
            i++;
            break;
          }
          i++;
        }
      } else if (ch === '{') {
        i++;
        const stack: string[] = ['{'];
        while (i < length && stack.length > 0) {
          const current = text[i];
          if (current === '"' || current === '\'') {
            const quote = current;
            i++;
            while (i < length) {
              if (text[i] === quote && text[i - 1] !== '\\') {
                i++;
                break;
              }
              i++;
            }
            continue;
          }
          if (current === '{') {
            stack.push('{');
          } else if (current === '}') {
            stack.pop();
          }
          i++;
        }
      } else {
        while (i < length && !/\s/.test(text[i])) {
          i++;
        }
      }

      const valueEndIndex = i;
      attr.valueStart = baseOffset + valueStartIndex;
      attr.valueEnd = baseOffset + valueEndIndex;
      attr.valueText = text.slice(valueStartIndex, valueEndIndex);
    }
  }

  // Log warning if we hit the iteration limit (indicates malformed input)
  if (iterations >= MAX_ITERATIONS) {
    console.warn('[parseAttributes] Hit iteration limit - possible malformed input');
  }

  return attributes;
}

export function findEnclosingComponentUsage(
  text: string,
  offset: number,
  cacheKey = '__anonymous__'
): ComponentUsage | null {
  const usages = collectComponentUsages(text, cacheKey);
  for (let i = usages.length - 1; i >= 0; i--) {
    const usage = usages[i];
    if (offset >= usage.openTagStart && offset <= usage.blockEnd) {
      return usage;
    }
  }
  return null;
}

export function getComponentUsageStack(
  text: string,
  offset: number,
  cacheKey = '__anonymous__'
): ComponentUsage[] {
  const usages = collectComponentUsages(text, cacheKey);
  return usages
    .filter(usage => offset >= usage.openTagStart && offset <= usage.blockEnd)
    .sort((a, b) => a.openTagStart - b.openTagStart);
}

/**
 * Async version of getComponentUsageStack that uses Elixir HEEx parser.
 * Returns stack of components that contain the given offset (ordered from outermost to innermost).
 *
 * @param text - HEEx template text
 * @param offset - Byte offset in text
 * @param filePath - Optional file path for Elixir parser
 * @param cacheKey - Cache key for tree-sitter/regex fallback
 * @returns Promise of component usage stack
 */
export async function getComponentUsageStackAsync(
  text: string,
  offset: number,
  filePath?: string,
  cacheKey = '__anonymous__'
): Promise<ComponentUsage[]> {
  const usages = await collectComponentUsagesAsync(text, filePath, cacheKey);
  return usages
    .filter(usage => offset >= usage.openTagStart && offset <= usage.blockEnd)
    .sort((a, b) => a.openTagStart - b.openTagStart);
}

function findTagEnd(text: string, startIndex: number): number {
  const stack: string[] = [];
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let i = startIndex;

  while (i < text.length) {
    const ch = text[i];
    const prev = i > 0 ? text[i - 1] : '';

    if (inSingleQuote) {
      if (ch === '\'' && prev !== '\\') {
        inSingleQuote = false;
      }
      i++;
      continue;
    }

    if (inDoubleQuote) {
      if (ch === '"' && prev !== '\\') {
        inDoubleQuote = false;
      }
      i++;
      continue;
    }

    if (ch === '\'') {
      inSingleQuote = true;
      i++;
      continue;
    }

    if (ch === '"') {
      inDoubleQuote = true;
      i++;
      continue;
    }

    if (ch === '{' || ch === '[' || ch === '(') {
      stack.push(ch);
      i++;
      continue;
    }

    if (ch === '}' || ch === ']' || ch === ')') {
      if (stack.length > 0) {
        stack.pop();
      }
      i++;
      continue;
    }

    if (ch === '>' && stack.length === 0) {
      return i;
    }

    i++;
  }

  return -1;
}

/**
 * Find ranges of nested components within the given content range
 * This is used to exclude slots that belong to child components
 */
function findNestedComponentRanges(
  text: string,
  contentStart: number,
  contentEnd: number
): Array<{ start: number; end: number }> {
  const ranges: Array<{ start: number; end: number }> = [];
  const contentSlice = text.slice(contentStart, contentEnd);

  // Match both local (<.component) and module (Module.component) components
  const componentPattern = /<(?:\.([a-z_][a-z0-9_]*)|([A-Z][\w]*(?:\.[A-Z][\w]*)*)\.([a-z_][a-z0-9_]*))\b/g;
  let match: RegExpExecArray | null;

  while ((match = componentPattern.exec(contentSlice)) !== null) {
    const componentName = match[1] || match[3]; // Local or module component name
    const moduleContext = match[2]; // Only for module components
    const isLocal = !!match[1];
    const openStart = contentStart + match.index;

    // Find the closing tag for this component
    const tagEnd = findTagEnd(text, openStart + match[0].length);
    if (tagEnd === -1) continue;

    // Check if self-closing
    let cursor = tagEnd - 1;
    while (cursor >= openStart && /\s/.test(text[cursor])) {
      cursor--;
    }
    const selfClosing = cursor >= openStart && text[cursor] === '/';

    if (selfClosing) {
      ranges.push({ start: openStart, end: tagEnd + 1 });
    } else {
      // Find closing tag
      const closing = findMatchingClosingTag(
        text,
        tagEnd + 1,
        componentName,
        moduleContext,
        isLocal
      );
      if (closing) {
        ranges.push({ start: openStart, end: closing.closeEnd });
      }
    }
  }

  return ranges;
}

function findMatchingClosingTag(
  text: string,
  searchStart: number,
  componentName: string,
  moduleContext: string | undefined,
  isLocal: boolean
): { closeStart: number; closeEnd: number } | null {
  const openTag = isLocal ? `<.${componentName}` : `<${moduleContext}.${componentName}`;
  const closeTag = isLocal ? `</.${componentName}` : `</${moduleContext}.${componentName}`;

  let depth = 1;
  let index = searchStart;

  while (index < text.length) {
    const nextOpen = text.indexOf(openTag, index);
    const nextClose = text.indexOf(closeTag, index);

    if (nextClose === -1) {
      return null;
    }

    if (nextOpen !== -1 && nextOpen < nextClose) {
      const openEnd = findTagEnd(text, nextOpen + openTag.length);
      if (openEnd === -1) {
        return null;
      }
      depth++;
      index = openEnd + 1;
      continue;
    }

    const closeHeadEnd = nextClose + closeTag.length;
    const closeTagEnd = findTagEnd(text, closeHeadEnd);
    if (closeTagEnd === -1) {
      return null;
    }

    depth--;
    if (depth === 0) {
      return { closeStart: nextClose, closeEnd: closeTagEnd + 1 };
    }

    index = closeTagEnd + 1;
  }

  return null;
}
