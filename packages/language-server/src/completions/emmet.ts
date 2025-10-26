import { CompletionItem, CompletionItemKind, Position } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import * as emmet from '@vscode/emmet-helper';

/**
 * Checks if the cursor position is inside Elixir expression braces {}.
 * Handles nested braces correctly.
 */
function isInsideElixirExpression(text: string, offset: number): boolean {
  let depth = 0;

  // Scan backwards from cursor position
  for (let i = offset - 1; i >= 0; i--) {
    const char = text[i];

    if (char === '}') {
      depth++;
    } else if (char === '{') {
      depth--;

      // If we find an unmatched opening brace, we're inside an expression
      if (depth < 0) {
        return true;
      }
    }
  }

  return false;
}

/**
 * Checks if the cursor position is inside a ~H sigil (HEEx embedded in Elixir).
 * Supports both ~H""" (triple quotes) and ~H" (single line).
 * Only matches uppercase ~H (not ~h).
 */
function isInsideHEExSigil(text: string, offset: number): boolean {
  // Scan backwards to find the most recent ~H sigil opening
  const beforeCursor = text.substring(0, offset);

  // Check for triple quotes FIRST (they're more specific)
  const tripleDoubleMatch = beforeCursor.lastIndexOf('~H"""');
  const tripleSingleMatch = beforeCursor.lastIndexOf("~H'''");

  // Find the most recent triple-quote opening
  let openingPos = -1;
  let delimiter = '';

  if (tripleDoubleMatch > tripleSingleMatch) {
    openingPos = tripleDoubleMatch;
    delimiter = '"""';
  } else if (tripleSingleMatch >= 0) {
    openingPos = tripleSingleMatch;
    delimiter = "'''";
  }

  // If no triple quotes found, check for single-line ~H"
  if (openingPos === -1) {
    const singleQuoteMatch = beforeCursor.lastIndexOf('~H"');
    if (singleQuoteMatch >= 0) {
      // Make sure it's NOT a triple quote by checking what comes after
      const afterMatch = text.substring(singleQuoteMatch + 2, singleQuoteMatch + 5);
      if (afterMatch === '"""' || afterMatch === "'''") {
        // This is actually a triple quote, skip it
        return false;
      }
      openingPos = singleQuoteMatch;
      delimiter = '"';
    }
  }

  // No sigil found before cursor
  if (openingPos === -1) {
    console.log('[isInsideHEExSigil] No ~H sigil found before cursor');
    return false;
  }

  console.log('[isInsideHEExSigil] Found ~H sigil at position', openingPos, 'with delimiter:', delimiter);

  // Check if there's a closing delimiter between opening and cursor
  const afterOpening = text.substring(openingPos + 2 + delimiter.length, offset); // +2 for ~H
  const closingPos = afterOpening.indexOf(delimiter);

  console.log('[isInsideHEExSigil] Closing delimiter found?', closingPos !== -1);

  // If no closing found, we're inside the sigil
  // If closing found, we're outside (sigil already closed)
  return closingPos === -1;
}

export async function getEmmetCompletions(
  document: TextDocument,
  position: Position,
  linePrefix: string,
  text: string,
  offset: number
): Promise<CompletionItem[]> {
  try {
    const isElixirFile = document.uri.endsWith('.ex') || document.uri.endsWith('.exs');
    const isHeexFile = document.uri.endsWith('.heex');

    console.log('[EMMET] ==================================');
    console.log('[EMMET] Request received');
    console.log('[EMMET] File type:', isElixirFile ? '.ex' : isHeexFile ? '.heex' : 'other');
    console.log('[EMMET] linePrefix:', JSON.stringify(linePrefix));
    console.log('[EMMET] offset:', offset);

    // Context-aware filtering: Skip emmet inside Elixir expressions
    // Skip if cursor is inside {} braces (Elixir expressions)
    if (isInsideElixirExpression(text, offset)) {
      console.log('[EMMET] Skipping: inside Elixir expression {}');
      return [];
    }

    // For .ex/.exs files, only provide emmet inside ~H sigils
    if (isElixirFile) {
      const insideSigil = isInsideHEExSigil(text, offset);
      console.log('[EMMET] .ex file - inside ~H sigil?', insideSigil);
      if (!insideSigil) {
        console.log('[EMMET] Skipping: not inside ~H sigil');
        return [];
      }
    }

    // Check if we should provide Emmet completions
    // Liberal pattern - let Emmet library validate what's valid
    // Supports all Emmet features:
    //   - Child (>), Sibling (+), Multiply (*), Numbering ($), Text ({})
    //   - Climb-up (^): div>ul>li^div
    //   - Grouping (()): (div>h1)+(div>p)
    //   - Attributes ([]): a[href=# target=_blank]
    //   - Or (|): span|div
    //   - Classes (.container), IDs (#header), Elements (div, ul, li)
    const emmetPattern = /(?:^|[\s>])([.#([]?[^\s]*)$/i;
    const match = linePrefix.match(emmetPattern);

    console.log('[EMMET] Pattern match:', match ? match[1] : 'NO MATCH');

    if (!match) {
      console.log('[EMMET] Skipping: no emmet pattern match');
      return [];
    }

    const abbreviation = match[1];

    // Skip Phoenix-specific snippets (let phoenix-snippets.ts handle these)
    // Component shortcuts: .live, .modal, .form, .table, .link, .button, .input
    const componentShortcuts = ['live', 'modal', 'form', 'table', 'link', 'button', 'input'];
    const componentMatch = abbreviation.match(/^\.([a-z]+)$/);
    if (componentMatch && componentShortcuts.includes(componentMatch[1])) {
      console.log('[EMMET] Skipping: Phoenix component shortcut detected');
      return [];
    }

    // Layout shortcuts: .hero, .card, .grid, .container, .section
    const layoutShortcuts = ['hero', 'card', 'grid', 'container', 'section'];
    if (componentMatch && layoutShortcuts.includes(componentMatch[1])) {
      console.log('[EMMET] Skipping: Phoenix layout shortcut detected');
      return [];
    }

    // HEEx shortcuts: :for, :if, :unless, :let
    if (/^:[a-z]+$/.test(abbreviation)) {
      console.log('[EMMET] Skipping: HEEx shortcut detected');
      return [];
    }

    // Phoenix patterns: form.phx, link.phx, btn.phx, etc.
    if (/\.(?:phx|loading|error|nav|patch|href|static|css|js|text|email|password|number)$/.test(abbreviation)) {
      console.log('[EMMET] Skipping: Phoenix pattern detected');
      return [];
    }

    // Event shortcuts: @click, @submit, etc.
    if (/^@[a-z]+/.test(abbreviation)) {
      console.log('[EMMET] Skipping: Phoenix event shortcut detected');
      return [];
    }

    // Stream shortcut
    if (abbreviation === 'stream') {
      console.log('[EMMET] Skipping: Phoenix stream shortcut detected');
      return [];
    }

    // Allow all other abbreviations
    // The emmet library will handle what's valid

    // Use the emmet helper to expand abbreviations
    const emmetCompletions = emmet.doComplete(
      document,
      position,
      'html',
      {
        showExpandedAbbreviation: 'always',
        showAbbreviationSuggestions: true,
        showSuggestionsAsSnippets: true,
        preferences: {},
      }
    );

    if (!emmetCompletions || !emmetCompletions.items) {
      console.log('[EMMET] No completions returned from emmet library');
      return [];
    }

    console.log('[EMMET] SUCCESS! Found', emmetCompletions.items.length, 'completions');

    // Convert Emmet completions to our format
    const results = emmetCompletions.items.map((item, index) => {
      console.log('[EMMET] Raw item from emmet library:', {
        label: item.label,
        insertText: item.insertText,
        textEdit: item.textEdit,
        insertTextFormat: item.insertTextFormat,
      });

      // Use textEdit if available (this properly replaces the abbreviation)
      // Otherwise fall back to insertText
      const completion: any = {
        label: item.label,
        kind: CompletionItemKind.Snippet,
        detail: 'Emmet abbreviation',
        documentation: item.documentation,
        insertTextFormat: 2, // Snippet format
        sortText: `!!!${index.toString().padStart(3, '0')}`, // Ultra-high priority (multiple ! for highest sort)
        filterText: abbreviation, // Use typed abbreviation for VS Code's fuzzy matcher
        preselect: index === 0, // Preselect first (most relevant) completion
      };

      // Prefer textEdit over insertText (textEdit replaces the abbreviation correctly)
      if (item.textEdit && 'newText' in item.textEdit) {
        completion.textEdit = item.textEdit;
        console.log('[EMMET] Using textEdit:', {
          newText: (item.textEdit as any).newText?.substring(0, 50),
          range: item.textEdit.range,
        });
      } else if (typeof item.insertText === 'string') {
        completion.insertText = item.insertText;
      } else if (item.insertText && typeof item.insertText === 'object' && 'value' in item.insertText) {
        completion.insertText = (item.insertText as any).value;
      } else if (item.label) {
        // Fallback: use label if nothing else works
        console.log('[EMMET] WARNING: Using label as fallback');
        completion.insertText = item.label;
      }

      return completion;
    });

    console.log('[EMMET] Returning', results.length, 'formatted completions');
    return results;
  } catch (error) {
    console.log('[EMMET] ERROR:', error);
    // Silently fail if Emmet expansion fails
    return [];
  }
}
