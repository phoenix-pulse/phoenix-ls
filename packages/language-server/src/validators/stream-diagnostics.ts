import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

/**
 * Validate Phoenix LiveView stream usage
 *
 * Streams are used for efficiently rendering large lists:
 * - Container must have phx-update="stream"
 * - Items must have id={dom_id} attribute
 * - Must destructure as {dom_id, item} tuple
 */
export function validateStreams(document: TextDocument): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Find all stream usages: @streams.name
  const streamPattern = /@streams\.([a-zA-Z_][a-zA-Z0-9_]*)/g;
  const streamUsages: Array<{ name: string; offset: number }> = [];

  let match: RegExpExecArray | null;
  while ((match = streamPattern.exec(text)) !== null) {
    streamUsages.push({
      name: match[1],
      offset: match.index,
    });
  }

  // Check each stream usage
  for (const usage of streamUsages) {
    // Find the :for loop containing this stream
    const forLoopContext = findEnclosingForLoop(text, usage.offset);

    if (!forLoopContext) {
      continue; // Stream used outside :for, might be valid (e.g., checking if stream exists)
    }

    // Validation 1: Check tuple destructuring pattern
    const hasTupleDestructure = /{{\s*\w+\s*,\s*\w+\s*}\s*<-\s*@streams\.\w+/.test(forLoopContext.forAttribute);

    if (!hasTupleDestructure) {
      // Check if they're using wrong pattern like: item <- @streams.users
      const wrongPattern = /(\w+)\s*<-\s*@streams\.\w+/.exec(forLoopContext.forAttribute);

      if (wrongPattern) {
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: {
            start: document.positionAt(forLoopContext.forStart),
            end: document.positionAt(forLoopContext.forEnd),
          },
          message: `Stream iteration must destructure tuple: Use \`{dom_id, ${wrongPattern[1]}} <- @streams.${usage.name}\` instead of \`${wrongPattern[1]} <- @streams.${usage.name}\``,
          source: 'phoenix-lsp',
          code: 'stream-invalid-pattern',
        });
      }
    }

    // Validation 2: Check for id={dom_id} attribute on the element
    const elementContext = findStreamElement(text, forLoopContext.elementStart, forLoopContext.elementEnd);

    if (elementContext) {
      // Extract the first variable from tuple destructure: {{dom_id, user}} -> dom_id
      const tupleMatch = forLoopContext.forAttribute.match(/\{\{\s*(\w+)\s*,/);
      const domIdVar = tupleMatch ? tupleMatch[1] : 'dom_id';

      const hasIdAttribute = new RegExp(`id\\s*=\\s*{${domIdVar}}`).test(elementContext.elementContent);

      if (!hasIdAttribute) {
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: {
            start: document.positionAt(elementContext.tagStart),
            end: document.positionAt(elementContext.tagEnd),
          },
          message: `Stream item must have \`id={${domIdVar}}\` attribute for LiveView to track DOM elements efficiently.`,
          source: 'phoenix-lsp',
          code: 'stream-missing-id',
        });
      }

      // Validation 3: Warn if using :key with streams (common mistake)
      if (/:key\s*=/.test(elementContext.elementContent)) {
        diagnostics.push({
          severity: DiagnosticSeverity.Warning,
          range: {
            start: document.positionAt(elementContext.tagStart),
            end: document.positionAt(elementContext.tagEnd),
          },
          message: `Streams use \`id={${domIdVar}}\` for DOM tracking, not \`:key\`. Remove \`:key\` attribute and ensure \`id={${domIdVar}}\` is present.`,
          source: 'phoenix-lsp',
          code: 'stream-unnecessary-key',
        });
      }
    }

    // Validation 4: Check for phx-update="stream" on container
    // This is a simplified check - we look for phx-update="stream" somewhere before the :for
    // More sophisticated parent-finding would require proper HTML parsing
    const textBeforeFor = text.substring(Math.max(0, forLoopContext.elementStart - 500), forLoopContext.elementStart);
    const hasPhxUpdateStream = /phx-update\s*=\s*["']stream["']/.test(textBeforeFor);

    // Also check if the element itself has phx-update="stream"
    const elementTag = text.substring(forLoopContext.elementStart, forLoopContext.elementEnd);
    const elementHasPhxUpdate = /phx-update\s*=\s*["']stream["']/.test(elementTag);

    if (!hasPhxUpdateStream && !elementHasPhxUpdate) {
      // Find a reasonable range for the diagnostic (use the opening tag)
      const tagEnd = text.indexOf('>', forLoopContext.elementStart);
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,  // Warning instead of Error - might be on parent we can't detect
        range: {
          start: document.positionAt(forLoopContext.elementStart),
          end: document.positionAt(tagEnd > 0 ? tagEnd + 1 : forLoopContext.elementEnd),
        },
        message: `Stream \`@streams.${usage.name}\` should have \`phx-update="stream"\` on this element or a parent container for efficient updates.`,
        source: 'phoenix-lsp',
        code: 'stream-missing-phx-update',
      });
    }
  }

  return diagnostics;
}

/**
 * Find the :for loop that contains the given offset
 */
function findEnclosingForLoop(text: string, offset: number): {
  forStart: number;
  forEnd: number;
  forAttribute: string;
  elementStart: number;
  elementEnd: number;
} | null {
  // Search backwards for :for attribute
  let searchStart = Math.max(0, offset - 500); // Look back 500 chars
  let searchText = text.substring(searchStart, offset + 100);

  // Find :for={...} pattern before the offset
  const forPattern = /:for\s*=\s*\{([^}]+)\}/g;
  let lastMatch: RegExpExecArray | null = null;
  let match: RegExpExecArray | null;

  while ((match = forPattern.exec(searchText)) !== null) {
    const matchOffset = searchStart + match.index;
    if (matchOffset < offset) {
      lastMatch = match;
    }
  }

  if (!lastMatch) {
    return null;
  }

  const forStart = searchStart + lastMatch.index;
  const forEnd = forStart + lastMatch[0].length;
  const forAttribute = lastMatch[0];

  // Find the element that contains this :for
  // Search backwards from :for to find opening <
  let tagStart = forStart;
  while (tagStart > 0 && text[tagStart] !== '<') {
    tagStart--;
  }

  // Find the closing > of the opening tag
  let tagEnd = forEnd;
  while (tagEnd < text.length && text[tagEnd] !== '>') {
    tagEnd++;
  }

  return {
    forStart,
    forEnd,
    forAttribute,
    elementStart: tagStart,
    elementEnd: tagEnd + 1,
  };
}

/**
 * Find the element that this :for is on
 */
function findStreamElement(text: string, elementStart: number, elementEnd: number): {
  tagStart: number;
  tagEnd: number;
  elementContent: string;
} | null {
  return {
    tagStart: elementStart,
    tagEnd: elementEnd,
    elementContent: text.substring(elementStart, elementEnd),
  };
}

/**
 * Find the container element that should have phx-update="stream"
 *
 * The container is the element that directly contains the :for loop.
 * We need to check if this element (or the element with the :for) has phx-update="stream"
 */
function findStreamContainer(text: string, elementStart: number): {
  start: number;
  end: number;
  hasPhxUpdateStream: boolean;
} | null {
  // First, check if the element itself has phx-update="stream"
  // Find the opening tag that contains elementStart
  let tagStart = elementStart;
  let tagEnd = elementStart;

  // Find start of tag (the '<' character)
  while (tagStart > 0 && text[tagStart] !== '<') {
    tagStart--;
  }

  // Find end of opening tag (the '>' character)
  while (tagEnd < text.length && text[tagEnd] !== '>') {
    tagEnd++;
  }

  const currentTag = text.substring(tagStart, tagEnd + 1);

  // Check if current tag has phx-update="stream"
  if (/phx-update\s*=\s*["']stream["']/.test(currentTag)) {
    return {
      start: tagStart,
      end: tagEnd + 1,
      hasPhxUpdateStream: true,
    };
  }

  // If not on current tag, look for parent container
  // Search backwards to find parent opening tag
  let depth = 0;
  let pos = tagStart - 1;
  let parentStart = -1;

  while (pos > 0) {
    if (text[pos] === '>' && text[pos - 1] !== '/') {
      // Found closing tag or end of opening tag
      depth++;
    } else if (text[pos] === '<' && text[pos + 1] !== '/') {
      // Found opening tag (not a closing tag)
      if (depth === 0) {
        parentStart = pos;
        break;
      }
      depth--;
    }
    pos--;
  }

  if (parentStart === -1) {
    return null;
  }

  // Find the end of parent opening tag
  let parentEnd = parentStart;
  while (parentEnd < text.length && text[parentEnd] !== '>') {
    parentEnd++;
  }

  const parentTag = text.substring(parentStart, parentEnd + 1);
  const hasPhxUpdateStream = /phx-update\s*=\s*["']stream["']/.test(parentTag);

  return {
    start: parentStart,
    end: parentEnd + 1,
    hasPhxUpdateStream,
  };
}
