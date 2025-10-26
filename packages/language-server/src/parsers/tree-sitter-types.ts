/**
 * TypeScript type definitions for web-tree-sitter
 *
 * These types are based on the actual usage patterns in our codebase.
 * They provide compile-time safety for tree-sitter operations.
 */

export interface Point {
  row: number;
  column: number;
}

export interface Range {
  startIndex: number;
  endIndex: number;
  startPosition: Point;
  endPosition: Point;
}

export interface Edit {
  startIndex: number;
  oldEndIndex: number;
  newEndIndex: number;
  startPosition: Point;
  oldEndPosition: Point;
  newEndPosition: Point;
}

export interface SyntaxNode {
  type: string;
  startIndex: number;
  endIndex: number;
  startPosition: Point;
  endPosition: Point;
  children: SyntaxNode[];
  namedChildren: SyntaxNode[];
  childForFieldName(fieldName: string): SyntaxNode | null;
  parent: SyntaxNode | null;
  nextSibling: SyntaxNode | null;
  previousSibling: SyntaxNode | null;
  text: string;
  isNamed: boolean;
  isMissing: boolean;
  hasError: boolean;
}

export interface Tree {
  rootNode: SyntaxNode;
  edit(edit: Edit): void;
  walk(): TreeCursor;
  getChangedRanges(other: Tree): Range[];
  getEditedRange(edit: Edit): Range;
}

export interface TreeCursor {
  nodeType: string;
  nodeText: string;
  nodeIsNamed: boolean;
  currentNode: SyntaxNode;
  gotoFirstChild(): boolean;
  gotoNextSibling(): boolean;
  gotoParent(): boolean;
  reset(node: SyntaxNode): void;
}

export interface Language {
  readonly version: number;
  readonly fieldCount: number;
  readonly nodeTypeCount: number;
}

export interface Parser {
  parse(input: string, oldTree?: Tree): Tree;
  setLanguage(language: Language): void;
  getLanguage(): Language;
  reset(): void;
  setTimeoutMicros(timeout: number): void;
  getTimeoutMicros(): number;
}

export interface ParserConstructor {
  new (): Parser;
}

export interface LanguageConstructor {
  load(path: string): Promise<Language>;
}

export interface TreeSitter {
  init(options?: {
    locateFile?: (scriptName: string, scriptDirectory?: string) => string;
  }): Promise<void>;
  Language: LanguageConstructor;
  Parser: ParserConstructor;
}
