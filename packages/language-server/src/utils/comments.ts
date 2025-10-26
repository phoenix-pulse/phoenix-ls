import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position, Range, Diagnostic } from 'vscode-languageserver/node';

interface CommentRange {
  start: number;
  end: number;
}

function collectHeexCommentRanges(text: string): CommentRange[] {
  const ranges: CommentRange[] = [];
  const patterns: Array<{ start: string; end: string }> = [
    { start: '<%!--', end: '--%>' },
    { start: '<!--', end: '-->' },
  ];

  for (const pattern of patterns) {
    let searchStart = 0;
    while (searchStart < text.length) {
      const begin = text.indexOf(pattern.start, searchStart);
      if (begin === -1) {
        break;
      }
      const afterBegin = begin + pattern.start.length;
      const end = text.indexOf(pattern.end, afterBegin);
      if (end === -1) {
        // Unterminated comment: consume until EOF
        ranges.push({ start: begin, end: text.length });
        break;
      }
      ranges.push({ start: begin, end: end + pattern.end.length });
      searchStart = end + pattern.end.length;
    }
  }

  return mergeRanges(ranges);
}

function collectElixirCommentRanges(text: string): CommentRange[] {
  const ranges: CommentRange[] = [];
  const lines = text.split('\n');
  let offset = 0;

  for (const line of lines) {
    const trimmed = line.trimStart();
    if (trimmed.startsWith('#')) {
      ranges.push({ start: offset, end: offset + line.length });
    }
    offset += line.length + 1; // include newline
  }

  const docRegex = /@(doc|moduledoc|typedoc)\s+(~[A-Za-z])?("""|''')/g;
  let match: RegExpExecArray | null;
  while ((match = docRegex.exec(text)) !== null) {
    const sigil = match[2] ?? '';
    const quotes = match[3];
    const delimiter = `${sigil}${quotes}`;
    const delimiterIndex = docRegex.lastIndex - quotes.length;
    const contentStart = sigil ? delimiterIndex - sigil.length : delimiterIndex;
    const closingIndex = text.indexOf(quotes, delimiterIndex + quotes.length);
    if (closingIndex === -1) {
      ranges.push({ start: contentStart, end: text.length });
      break;
    }
    ranges.push({ start: contentStart, end: closingIndex + quotes.length });
    docRegex.lastIndex = closingIndex + quotes.length;
  }

  return mergeRanges(ranges);
}

function mergeRanges(ranges: CommentRange[]): CommentRange[] {
  if (ranges.length === 0) {
    return ranges;
  }

  const sorted = ranges.sort((a, b) => a.start - b.start);
  const merged: CommentRange[] = [];
  let current = sorted[0];

  for (let i = 1; i < sorted.length; i++) {
    const range = sorted[i];
    if (range.start <= current.end) {
      current.end = Math.max(current.end, range.end);
    } else {
      merged.push(current);
      current = range;
    }
  }
  merged.push(current);
  return merged;
}

function isOffsetInRanges(offset: number, ranges: CommentRange[]): boolean {
  return ranges.some(range => offset >= range.start && offset <= range.end);
}

export function filterDiagnosticsInsideComments(
  document: TextDocument,
  diagnostics: Diagnostic[]
): Diagnostic[] {
  if (diagnostics.length === 0) {
    return diagnostics;
  }

  const uri = document.uri;
  const text = document.getText();
  const isHeex = uri.endsWith('.heex');
  const isElixir = uri.endsWith('.ex') || uri.endsWith('.exs');

  const commentRanges: CommentRange[] = [];
  if (isHeex) {
    commentRanges.push(...collectHeexCommentRanges(text));
  } else if (isElixir) {
    commentRanges.push(...collectElixirCommentRanges(text));
  }

  if (commentRanges.length === 0) {
    return diagnostics;
  }

  return diagnostics.filter(diagnostic => {
    const startOffset = document.offsetAt(diagnostic.range.start);
    const endOffset = document.offsetAt(diagnostic.range.end);
    const midpoint = Math.floor((startOffset + endOffset) / 2);

    return !(
      isOffsetInRanges(startOffset, commentRanges) &&
      isOffsetInRanges(endOffset, commentRanges) &&
      isOffsetInRanges(midpoint, commentRanges)
    );
  });
}
