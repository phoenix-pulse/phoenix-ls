export type EmbeddedLanguageId = 'html' | 'css' | 'javascript';

export interface PositionLike {
  line: number;
  character: number;
}

export interface EmbeddedDocumentInput {
  uri: string;
  languageId: string;
  text: string;
  position: PositionLike;
}

export interface EmbeddedVirtualDocument {
  languageId: EmbeddedLanguageId;
  sourceUri: string;
  virtualUri: string;
  virtualText: string;
  sourceToVirtual(position: PositionLike): PositionLike;
  virtualToSource(position: PositionLike): PositionLike;
}

interface SourceRegion {
  startOffset: number;
  endOffset: number;
  languageId: EmbeddedLanguageId;
}

export function embeddedDocumentAt(input: EmbeddedDocumentInput): EmbeddedVirtualDocument | null {
  const lineStarts = lineStartOffsets(input.text);
  const cursorOffset = offsetAt(input.position, lineStarts, input.text.length);
  const htmlRegion = htmlRegionAt(input, cursorOffset);

  if (!htmlRegion) {
    return null;
  }

  const nestedRegion =
    tagContentRegionAt(input.text, htmlRegion, cursorOffset, 'style', 'css') ||
    tagContentRegionAt(input.text, htmlRegion, cursorOffset, 'script', 'javascript');

  const region = nestedRegion || htmlRegion;

  return {
    languageId: region.languageId,
    sourceUri: input.uri,
    virtualUri: virtualUri(input.uri, region.languageId),
    virtualText: maskOutsideRegion(input.text, region),
    sourceToVirtual(position: PositionLike): PositionLike {
      return position;
    },
    virtualToSource(position: PositionLike): PositionLike {
      return position;
    }
  };
}

function htmlRegionAt(input: EmbeddedDocumentInput, cursorOffset: number): SourceRegion | null {
  if (input.languageId === 'phoenix-heex' || input.uri.endsWith('.heex')) {
    return {
      startOffset: 0,
      endOffset: input.text.length,
      languageId: 'html'
    };
  }

  if (input.languageId === 'elixir' || input.uri.endsWith('.ex') || input.uri.endsWith('.exs')) {
    return sigilRegionAt(input.text, cursorOffset);
  }

  return null;
}

function sigilRegionAt(text: string, cursorOffset: number): SourceRegion | null {
  let offset = 0;

  while (offset < text.length - 2) {
    if (text[offset] !== '~' || lower(text[offset + 1]) !== 'h') {
      offset += 1;
      continue;
    }

    const delimiter = text[offset + 2];
    const region = delimiter === '"' || delimiter === "'"
      ? quotedSigilRegion(text, offset + 2, delimiter)
      : bracketSigilRegion(text, offset + 2, delimiter);

    if (region && cursorOffset >= region.startOffset && cursorOffset <= region.endOffset) {
      return region;
    }

    offset = region ? region.endOffset + 1 : offset + 1;
  }

  return null;
}

function quotedSigilRegion(
  text: string,
  delimiterOffset: number,
  delimiter: string
): SourceRegion | null {
  const heredoc =
    text[delimiterOffset + 1] === delimiter && text[delimiterOffset + 2] === delimiter;

  if (heredoc) {
    const contentStart = delimiterOffset + 3;
    const closeOffset = findTripleDelimiter(text, contentStart, delimiter);

    if (closeOffset === -1) {
      return null;
    }

    return {
      startOffset: contentStart,
      endOffset: closeOffset,
      languageId: 'html'
    };
  }

  const contentStart = delimiterOffset + 1;
  const closeOffset = findSingleDelimiter(text, contentStart, delimiter);

  if (closeOffset === -1) {
    return null;
  }

  return {
    startOffset: contentStart,
    endOffset: closeOffset,
    languageId: 'html'
  };
}

function bracketSigilRegion(text: string, delimiterOffset: number, delimiter: string): SourceRegion | null {
  const closing = matchingDelimiter(delimiter);

  if (!closing) {
    return null;
  }

  const contentStart = delimiterOffset + 1;
  const closeOffset = findSingleDelimiter(text, contentStart, closing);

  if (closeOffset === -1) {
    return null;
  }

  return {
    startOffset: contentStart,
    endOffset: closeOffset,
    languageId: 'html'
  };
}

function tagContentRegionAt(
  text: string,
  htmlRegion: SourceRegion,
  cursorOffset: number,
  tagName: 'style' | 'script',
  languageId: EmbeddedLanguageId
): SourceRegion | null {
  const lowerText = text.toLowerCase();
  const openNeedle = `<${tagName}`;
  const closeNeedle = `</${tagName}>`;
  let searchOffset = htmlRegion.startOffset;

  while (searchOffset < htmlRegion.endOffset) {
    const openStart = lowerText.indexOf(openNeedle, searchOffset);

    if (openStart === -1 || openStart >= htmlRegion.endOffset) {
      return null;
    }

    const openEnd = text.indexOf('>', openStart);

    if (openEnd === -1 || openEnd >= htmlRegion.endOffset) {
      return null;
    }

    const contentStart = openEnd + 1;
    const closeStart = lowerText.indexOf(closeNeedle, contentStart);

    if (closeStart === -1 || closeStart > htmlRegion.endOffset) {
      return null;
    }

    if (cursorOffset >= contentStart && cursorOffset <= closeStart) {
      return {
        startOffset: contentStart,
        endOffset: closeStart,
        languageId
      };
    }

    searchOffset = closeStart + closeNeedle.length;
  }

  return null;
}

function maskOutsideRegion(text: string, region: SourceRegion): string {
  if (region.startOffset === 0 && region.endOffset === text.length) {
    return text;
  }

  let result = '';

  for (let offset = 0; offset < text.length; offset += 1) {
    if (offset >= region.startOffset && offset < region.endOffset) {
      result += text[offset];
    } else {
      result += text[offset] === '\n' ? '\n' : ' ';
    }
  }

  return result;
}

function lineStartOffsets(text: string): number[] {
  const starts = [0];

  for (let offset = 0; offset < text.length; offset += 1) {
    if (text[offset] === '\n') {
      starts.push(offset + 1);
    }
  }

  return starts;
}

function offsetAt(position: PositionLike, starts: number[], textLength: number): number {
  const line = Math.max(0, Math.min(position.line, starts.length - 1));
  const lineStart = starts[line];
  const nextLineStart = starts[line + 1] ?? textLength + 1;
  const lineEnd = Math.max(lineStart, nextLineStart - 1);

  return Math.max(lineStart, Math.min(lineStart + Math.max(0, position.character), lineEnd));
}

function findTripleDelimiter(text: string, startOffset: number, delimiter: string): number {
  for (let offset = startOffset; offset < text.length - 2; offset += 1) {
    if (
      text[offset] === delimiter &&
      text[offset + 1] === delimiter &&
      text[offset + 2] === delimiter
    ) {
      return offset;
    }
  }

  return -1;
}

function findSingleDelimiter(text: string, startOffset: number, delimiter: string): number {
  for (let offset = startOffset; offset < text.length; offset += 1) {
    if (text[offset] === delimiter && text[offset - 1] !== '\\') {
      return offset;
    }
  }

  return -1;
}

function matchingDelimiter(delimiter: string): string | null {
  switch (delimiter) {
    case '(':
      return ')';
    case '[':
      return ']';
    case '{':
      return '}';
    case '<':
      return '>';
    case '/':
      return '/';
    case '|':
      return '|';
    default:
      return null;
  }
}

function virtualUri(sourceUri: string, languageId: EmbeddedLanguageId): string {
  const extension = languageId === 'javascript' ? 'js' : languageId;
  return `phoenix-pulse-embedded:${encodeURIComponent(sourceUri)}.${extension}`;
}

function lower(value: string): string {
  return value.toLowerCase();
}
