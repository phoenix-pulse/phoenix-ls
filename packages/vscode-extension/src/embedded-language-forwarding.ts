import * as vscode from 'vscode';
import {
  EmbeddedVirtualDocument,
  PositionLike,
  embeddedDocumentAt
} from './embedded-languages';

const SCHEME = 'phoenix-pulse-embedded';
const SELECTOR = [{ language: 'phoenix-heex' }, { language: 'elixir' }];
const COMPLETION_TRIGGERS = ['<', '/', '.', ':', '"', "'", '{', '@'];

export function registerEmbeddedLanguageForwarding(
  context: vscode.ExtensionContext,
  outputChannel?: vscode.OutputChannel
): void {
  const store = new EmbeddedDocumentStore();
  const provider = new EmbeddedLanguageForwardingProvider(store, outputChannel);

  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider(SCHEME, store),
    vscode.languages.registerCompletionItemProvider(SELECTOR, provider, ...COMPLETION_TRIGGERS),
    vscode.languages.registerHoverProvider(SELECTOR, provider),
    vscode.languages.registerDefinitionProvider(SELECTOR, provider)
  );
}

class EmbeddedDocumentStore implements vscode.TextDocumentContentProvider {
  private documents = new Map<string, string>();
  private latestUri: string | null = null;

  upsert(uri: vscode.Uri, text: string): void {
    const key = uri.toString();
    this.documents.set(key, text);
    this.latestUri = key;
  }

  provideTextDocumentContent(uri?: vscode.Uri): string {
    const key = uri?.toString() ?? this.latestUri;
    return key ? this.documents.get(key) ?? '' : '';
  }
}

class EmbeddedLanguageForwardingProvider
  implements vscode.CompletionItemProvider, vscode.HoverProvider, vscode.DefinitionProvider
{
  constructor(
    private store: EmbeddedDocumentStore,
    private outputChannel?: vscode.OutputChannel
  ) {}

  async provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position,
    token: vscode.CancellationToken,
    context: vscode.CompletionContext
  ): Promise<vscode.CompletionList | vscode.CompletionItem[] | undefined> {
    const resolved = await this.resolve(document, position);

    if (!resolved) {
      return undefined;
    }

    return vscode.commands.executeCommand<vscode.CompletionList | vscode.CompletionItem[]>(
      'vscode.executeCompletionItemProvider',
      resolved.uri,
      resolved.position,
      context.triggerCharacter
    );
  }

  async provideHover(
    document: vscode.TextDocument,
    position: vscode.Position,
    _token: vscode.CancellationToken
  ): Promise<vscode.Hover[] | vscode.Hover | undefined> {
    const resolved = await this.resolve(document, position);

    if (!resolved) {
      return undefined;
    }

    return vscode.commands.executeCommand<vscode.Hover[]>(
      'vscode.executeHoverProvider',
      resolved.uri,
      resolved.position
    );
  }

  async provideDefinition(
    document: vscode.TextDocument,
    position: vscode.Position,
    _token: vscode.CancellationToken
  ): Promise<vscode.Definition | vscode.DefinitionLink[] | undefined> {
    const resolved = await this.resolve(document, position);

    if (!resolved) {
      return undefined;
    }

    const definition = await vscode.commands.executeCommand<vscode.Definition | vscode.DefinitionLink[]>(
      'vscode.executeDefinitionProvider',
      resolved.uri,
      resolved.position
    );

    return mapDefinitionResult(definition, document.uri, resolved.uri);
  }

  private async resolve(document: vscode.TextDocument, position: PositionLike): Promise<ResolvedEmbedded | null> {
    const embedded = embeddedDocumentAt({
      uri: document.uri.toString(),
      languageId: document.languageId,
      text: document.getText(),
      position
    });

    if (!embedded) {
      return null;
    }

    const virtualUri = vscode.Uri.parse(embedded.virtualUri);
    this.store.upsert(virtualUri, embedded.virtualText);

    try {
      await vscode.workspace.openTextDocument(virtualUri);
    } catch (error) {
      this.outputChannel?.appendLine(`[Phoenix Pulse] Embedded language virtual document failed: ${error}`);
      return null;
    }

    return {
      embedded,
      uri: virtualUri,
      position: toVSCodePosition(embedded.sourceToVirtual(position))
    };
  }
}

interface ResolvedEmbedded {
  embedded: EmbeddedVirtualDocument;
  uri: vscode.Uri;
  position: vscode.Position;
}

function mapDefinitionResult(
  result: vscode.Definition | vscode.DefinitionLink[] | undefined,
  sourceUri: vscode.Uri,
  virtualUri: vscode.Uri
): vscode.Definition | vscode.DefinitionLink[] | undefined {
  if (!result) {
    return result;
  }

  if (Array.isArray(result)) {
    return result.map(item => mapDefinitionItem(item, sourceUri, virtualUri));
  }

  return mapDefinitionItem(result, sourceUri, virtualUri) as vscode.Definition;
}

function mapDefinitionItem(
  item: vscode.Location | vscode.LocationLink,
  sourceUri: vscode.Uri,
  virtualUri: vscode.Uri
): vscode.Location | vscode.LocationLink {
  const candidate = item as any;

  if ('uri' in candidate && 'range' in candidate) {
    return embeddedUri(candidate.uri, virtualUri)
      ? new vscode.Location(sourceUri, candidate.range)
      : item;
  }

  if ('targetUri' in candidate && embeddedUri(candidate.targetUri, virtualUri)) {
    return {
      ...item,
      targetUri: sourceUri
    };
  }

  return item;
}

function embeddedUri(candidate: vscode.Uri | undefined, virtualUri: vscode.Uri): boolean {
  return candidate?.toString() === virtualUri.toString();
}

function toVSCodePosition(position: PositionLike): vscode.Position {
  return new vscode.Position(position.line, position.character);
}
