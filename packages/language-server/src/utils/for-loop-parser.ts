/**
 * Parser for HEEx :for loop patterns
 * Extracts loop variable information from :for attributes
 */

// Debug helper - only logs if PHOENIX_PULSE_DEBUG includes 'for-loop'
const debugLog = (message: string, ...args: any[]) => {
  if (process.env.PHOENIX_PULSE_DEBUG?.includes('for-loop')) {
    console.log(message, ...args);
  }
};

export interface ForLoopVariable {
  name: string;        // "image"
  source: string;      // "@product.images" or "product.images"
  baseAssign: string;  // "product"
  path: string[];      // ["images"]
  isFromAssign: boolean; // true if source is @assign, false if outer loop variable
  range: { start: number; end: number };
}

/**
 * Parse a :for loop attribute to extract variable information
 *
 * Supports patterns like:
 * - :for={image <- @product.images}  (assign access)
 * - :for={image <- product.images}   (outer loop variable access)
 * - :for={ image <- @product.images }
 * - :for={{id, image} <- @streams.images} (tuple destructuring)
 *
 * @param forAttribute - The :for attribute string (e.g., ":for={image <- @product.images}")
 * @param offset - Offset where the :for attribute starts
 * @returns Parsed variable info or null if pattern doesn't match
 */
export function parseForLoopVariable(forAttribute: string, offset: number = 0): ForLoopVariable | null {
  debugLog('[parseForLoopVariable] Input:', JSON.stringify(forAttribute));

  // Pattern 1: Direct list access (raffle <- @raffles)
  // This must come BEFORE the field access pattern to match correctly
  const directPattern = /\{?\s*(\w+)\s*<-\s*@(\w+)\s*\}?/;
  const directMatch = forAttribute.match(directPattern);

  debugLog('[parseForLoopVariable] directMatch:', directMatch);

  if (directMatch) {
    const varName = directMatch[1];
    const baseAssign = directMatch[2];

    debugLog('[parseForLoopVariable] Direct list:', { varName, baseAssign });

    return {
      name: varName,
      source: `@${baseAssign}`,
      baseAssign,
      path: [], // Empty path for direct access
      isFromAssign: true,
      range: { start: offset, end: offset + forAttribute.length }
    };
  }

  // Pattern 2: Field access with optional @ (image <- @product.images OR image <- product.images)
  // Use [\w.]{1,100} with bounded repetition to prevent catastrophic backtracking (DoS protection)
  const fieldPattern = /\{?\s*(\w+)\s*<-\s*(@?)(\w+)\.([\w.]{1,100})/;
  const fieldMatch = forAttribute.match(fieldPattern);

  debugLog('[parseForLoopVariable] fieldMatch:', fieldMatch);

  if (fieldMatch) {
    const varName = fieldMatch[1];
    const hasAt = fieldMatch[2] === '@';
    const baseAssign = fieldMatch[3];
    const pathStr = fieldMatch[4].trim(); // Already clean - no need to strip }
    const path = pathStr.split('.');

    debugLog('[parseForLoopVariable] Field access:', { varName, baseAssign, pathStr, path, hasAt });

    return {
      name: varName,
      source: hasAt ? `@${baseAssign}.${pathStr}` : `${baseAssign}.${pathStr}`,
      baseAssign,
      path,
      isFromAssign: hasAt,
      range: { start: offset, end: offset + forAttribute.length }
    };
  }

  // Pattern 3: Tuple destructuring with optional @ ({{id, image} <- @streams.images OR {{id, image} <- streams.images})
  // Use [\w.]{1,100} with bounded repetition to prevent catastrophic backtracking (DoS protection)
  const tuplePattern = /\{\{\s*\w+\s*,\s*(\w+)\s*\}\s*<-\s*(@?)(\w+)\.([\w.]{1,100})/;
  const tupleMatch = forAttribute.match(tuplePattern);

  debugLog('[parseForLoopVariable] tupleMatch:', tupleMatch);

  if (tupleMatch) {
    const varName = tupleMatch[1]; // Get second element of tuple
    const hasAt = tupleMatch[2] === '@';
    const baseAssign = tupleMatch[3];
    const pathStr = tupleMatch[4].trim(); // Already clean
    const path = pathStr.split('.');

    debugLog('[parseForLoopVariable] Tuple:', { varName, baseAssign, pathStr, path, hasAt });

    return {
      name: varName,
      source: hasAt ? `@${baseAssign}.${pathStr}` : `${baseAssign}.${pathStr}`,
      baseAssign,
      path,
      isFromAssign: hasAt,
      range: { start: offset, end: offset + forAttribute.length }
    };
  }

  debugLog('[parseForLoopVariable] No pattern matched');
  return null;
}

/**
 * Find the enclosing :for loop for a given cursor position
 *
 * @param text - Full document text
 * @param offset - Current cursor position
 * @returns For loop info or null if not inside a loop
 */
export function findEnclosingForLoop(text: string, offset: number): {
  forStart: number;
  forEnd: number;
  forAttribute: string;
  variable: ForLoopVariable | null;
  elementStart: number;
  elementEnd: number;
} | null {
  // Search backwards for :for attribute (max 50 lines for performance)
  // Find line boundaries instead of arbitrary character count
  const MAX_LINES = 50;
  let searchStart = offset;
  let lineCount = 0;

  // Walk backward counting newlines until we hit MAX_LINES or start of file
  while (searchStart > 0 && lineCount < MAX_LINES) {
    searchStart--;
    if (text[searchStart] === '\n') {
      lineCount++;
    }
  }

  const searchText = text.substring(searchStart, offset + 100);

  // Find :for= pattern before the offset
  // Use simple pattern to find start, then manually parse to handle nested braces
  const forStartPattern = /:for\s*=\s*\{/g;
  let lastForStart = -1;
  let lastForAttribute = '';
  let match: RegExpExecArray | null;

  while ((match = forStartPattern.exec(searchText)) !== null) {
    const matchOffset = searchStart + match.index;
    if (matchOffset >= offset) {
      break; // Don't search past cursor
    }

    // Found `:for={` - now manually find the matching closing brace
    const attrStart = match.index;
    const contentStart = attrStart + match[0].length;
    let braceDepth = 1; // We already have opening {
    let i = contentStart;

    debugLog('[findEnclosingForLoop] Found :for at', attrStart, 'searching for closing }');

    // Scan forward counting braces to find the matching closing }
    while (i < searchText.length && braceDepth > 0) {
      if (searchText[i] === '{') {
        braceDepth++;
      } else if (searchText[i] === '}') {
        braceDepth--;
      }
      i++;
    }

    if (braceDepth === 0) {
      // Found matching closing brace
      const forAttribute = searchText.substring(attrStart, i);
      debugLog('[findEnclosingForLoop] Complete attribute:', forAttribute);
      lastForStart = attrStart;
      lastForAttribute = forAttribute;
    }
  }

  if (lastForStart === -1) {
    return null;
  }

  const forStart = searchStart + lastForStart;
  const forEnd = forStart + lastForAttribute.length;
  const forAttribute = lastForAttribute;

  // Parse the variable
  const variable = parseForLoopVariable(forAttribute, forStart);

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
    variable,
    elementStart: tagStart,
    elementEnd: tagEnd + 1,
  };
}

/**
 * Check if a given position is inside a :for loop
 *
 * @param text - Full document text
 * @param offset - Current cursor position
 * @returns true if inside a loop, false otherwise
 */
export function isInsideForLoop(text: string, offset: number): boolean {
  return findEnclosingForLoop(text, offset) !== null;
}
