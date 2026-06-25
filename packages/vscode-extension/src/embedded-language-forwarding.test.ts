import { beforeEach, describe, expect, it, vi } from 'vitest';

const vscodeState = vi.hoisted(() => ({
  contentProvider: undefined as any,
  completionProvider: undefined as any,
  hoverProvider: undefined as any,
  definitionProvider: undefined as any,
  commands: [] as Array<{ command: string; args: unknown[] }>,
  openedDocuments: [] as unknown[],
  completionResult: [{ label: 'class' }]
}));

vi.mock('vscode', () => ({
  workspace: {
    registerTextDocumentContentProvider: vi.fn((scheme: string, provider: unknown) => {
      vscodeState.contentProvider = { scheme, provider };
      return { dispose: vi.fn() };
    }),
    openTextDocument: vi.fn(async (uri: unknown) => {
      vscodeState.openedDocuments.push(uri);
      return { uri };
    })
  },
  languages: {
    registerCompletionItemProvider: vi.fn((selector: unknown, provider: unknown, ...triggers: string[]) => {
      vscodeState.completionProvider = { selector, provider, triggers };
      return { dispose: vi.fn() };
    }),
    registerHoverProvider: vi.fn((selector: unknown, provider: unknown) => {
      vscodeState.hoverProvider = { selector, provider };
      return { dispose: vi.fn() };
    }),
    registerDefinitionProvider: vi.fn((selector: unknown, provider: unknown) => {
      vscodeState.definitionProvider = { selector, provider };
      return { dispose: vi.fn() };
    })
  },
  commands: {
    executeCommand: vi.fn(async (command: string, ...args: unknown[]) => {
      vscodeState.commands.push({ command, args });
      if (command === 'vscode.executeCompletionItemProvider') {
        return vscodeState.completionResult;
      }
      return [];
    })
  },
  Uri: {
    parse: vi.fn((value: string) => ({ value, toString: () => value }))
  },
  Position: class {
    constructor(public line: number, public character: number) {}
  },
  Range: class {
    constructor(public start: unknown, public end: unknown) {}
  }
}));

import { registerEmbeddedLanguageForwarding } from './embedded-language-forwarding';

describe('embedded language forwarding', () => {
  beforeEach(() => {
    vscodeState.contentProvider = undefined;
    vscodeState.completionProvider = undefined;
    vscodeState.hoverProvider = undefined;
    vscodeState.definitionProvider = undefined;
    vscodeState.commands = [];
    vscodeState.openedDocuments = [];
  });

  it('registers virtual document content plus completion, hover, and definition providers', () => {
    const context = { subscriptions: [] as unknown[] };

    registerEmbeddedLanguageForwarding(context as any);

    expect(vscodeState.contentProvider.scheme).toBe('phoenix-pulse-embedded');
    expect(vscodeState.completionProvider.selector).toEqual([
      { language: 'phoenix-heex' },
      { language: 'elixir' }
    ]);
    expect(vscodeState.completionProvider.triggers).toEqual(
      expect.arrayContaining(['<', '/', '.', ':', '"', "'", '{', '@'])
    );
    expect(vscodeState.hoverProvider.selector).toEqual([
      { language: 'phoenix-heex' },
      { language: 'elixir' }
    ]);
    expect(vscodeState.definitionProvider.selector).toEqual([
      { language: 'phoenix-heex' },
      { language: 'elixir' }
    ]);
    expect(context.subscriptions).toHaveLength(4);
  });

  it('forwards HEEx completion requests through a virtual HTML document', async () => {
    const context = { subscriptions: [] as unknown[] };
    registerEmbeddedLanguageForwarding(context as any);

    const sourceDocument = {
      uri: { toString: () => 'file:///tmp/page.html.heex' },
      languageId: 'phoenix-heex',
      getText: () => '<div cla></div>'
    };

    const result = await vscodeState.completionProvider.provider.provideCompletionItems(
      sourceDocument,
      { line: 0, character: 6 },
      {},
      { triggerCharacter: 'a' }
    );

    expect(result).toEqual([{ label: 'class' }]);
    expect(vscodeState.commands[0]).toMatchObject({
      command: 'vscode.executeCompletionItemProvider'
    });
    expect(vscodeState.commands[0].args[0]).toMatchObject({
      value: expect.stringContaining('file%3A%2F%2F%2Ftmp%2Fpage.html.heex.html')
    });
    expect(vscodeState.contentProvider.provider.provideTextDocumentContent()).toBe('<div cla></div>');
  });

  it('does not forward completion requests outside Elixir HEEx sigils', async () => {
    const context = { subscriptions: [] as unknown[] };
    registerEmbeddedLanguageForwarding(context as any);

    const result = await vscodeState.completionProvider.provider.provideCompletionItems(
      {
        uri: { toString: () => 'file:///tmp/page_live.ex' },
        languageId: 'elixir',
        getText: () => 'def render(assigns), do: assigns'
      },
      { line: 0, character: 4 },
      {},
      {}
    );

    expect(result).toBeUndefined();
    expect(vscodeState.commands).toEqual([]);
  });
});
