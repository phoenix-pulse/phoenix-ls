import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  DefinitionRequest
} from 'vscode-languageclient/node';
import { PhoenixPulseTreeProvider } from './tree-view-provider';
import { ErdProvider } from './diagrams/erd-provider';
import { resolveServer, type ResolvedServer } from './server-resolver';
import { maybeWriteDogfoodSnapshot } from './dogfood';
import { registerEmbeddedLanguageForwarding } from './embedded-language-forwarding';

let client: LanguageClient;
let clientReady: Promise<void> = Promise.resolve();

const EXPERT_EXTENSION_ID = 'ExpertLSP.expert';
const EXPERT_EXTENSION_IDS = [EXPERT_EXTENSION_ID, 'expertlsp.expert'];
const GENERIC_ELIXIR_LS_EXTENSION_IDS = [
  'JakeBecker.elixir-ls',
  'elixir-lsp.elixir-ls',
  'lexical-lsp.lexical',
  'elixir-tools.elixir-tools'
];

type PhoenixLSConfiguredMode = 'auto' | 'companion' | 'full';
type PhoenixLSResolvedMode = 'companion' | 'full';

export interface PhoenixLSModeResolution {
  configuredMode: PhoenixLSConfiguredMode;
  resolvedMode: PhoenixLSResolvedMode;
  detectedExpert: boolean;
  detectedGenericElixirLS: boolean;
  detectedCompanionPeer: boolean;
  detectExpert: boolean;
  disableGenericElixir: boolean;
  env: Record<string, string>;
}

export function resolvePhoenixLSMode(): PhoenixLSModeResolution {
  const config = vscode.workspace.getConfiguration('phoenixLS');
  const configuredMode = normalizePhoenixLSMode(config.get<string>('mode', 'auto'));
  const detectExpert = config.get<boolean>('companion.detectExpert', true);
  const disableGenericElixir = config.get<boolean>('companion.disableGenericElixir', true);
  const detectedExpert = detectExpert && installedPeer(EXPERT_EXTENSION_IDS, expertExtension);
  const detectedGenericElixirLS =
    detectExpert && installedPeer(GENERIC_ELIXIR_LS_EXTENSION_IDS, genericElixirExtension);
  const detectedCompanionPeer = detectedExpert || detectedGenericElixirLS;
  const resolvedMode = configuredMode === 'auto'
    ? detectedCompanionPeer ? 'companion' : 'full'
    : configuredMode;

  return {
    configuredMode,
    resolvedMode,
    detectedExpert,
    detectedGenericElixirLS,
    detectedCompanionPeer,
    detectExpert,
    disableGenericElixir,
    env: {
      PHOENIX_LS_MODE: configuredMode,
      PHOENIX_LS_DETECTED_EXPERT: detectedExpert ? 'true' : 'false',
      PHOENIX_LS_DETECTED_COMPANION_PEER: detectedCompanionPeer ? 'true' : 'false',
      PHOENIX_LS_DISABLE_GENERIC_ELIXIR: disableGenericElixir ? 'true' : 'false'
    }
  };
}

export function describePhoenixLSMode(mode: PhoenixLSModeResolution): string {
  return `Phoenix LS mode: ${mode.resolvedMode} (${describePhoenixLSExpertDetection(mode)})`;
}

export function buildPhoenixLSServerOptions(
  resolvedServer: ResolvedServer,
  mode: PhoenixLSModeResolution = resolvePhoenixLSMode()
): ServerOptions {
  const env = {
    ...resolvedServer.env,
    ...mode.env
  };

  return {
    run: {
      command: resolvedServer.command,
      args: resolvedServer.args,
      options: { env }
    },
    debug: {
      command: resolvedServer.command,
      args: resolvedServer.args,
      options: { env: { ...env, PHOENIX_LS_LOG_LEVEL: 'debug' } }
    }
  };
}

function normalizePhoenixLSMode(value: unknown): PhoenixLSConfiguredMode {
  if (value === 'companion' || value === 'full') {
    return value;
  }

  return 'auto';
}

function installedPeer(
  extensionIds: string[],
  fallbackMatcher: (extension: vscode.Extension<unknown>) => boolean
): boolean {
  const normalizedIds = extensionIds.map(id => id.toLowerCase());

  if (extensionIds.some(id => Boolean(vscode.extensions.getExtension(id)))) {
    return true;
  }

  return vscode.extensions.all.some(extension => {
    const id = extension.id.toLowerCase();
    return normalizedIds.includes(id) || fallbackMatcher(extension);
  });
}

function expertExtension(extension: vscode.Extension<unknown>): boolean {
  const id = extension.id.toLowerCase();
  if (id === EXPERT_EXTENSION_ID.toLowerCase()) {
    return true;
  }

  const metadata = extensionMetadata(extension);
  return metadata.includes('expert') && metadata.includes('elixir');
}

function genericElixirExtension(extension: vscode.Extension<unknown>): boolean {
  const id = extension.id.toLowerCase();

  return GENERIC_ELIXIR_LS_EXTENSION_IDS.some(peer => id === peer.toLowerCase());
}

function extensionMetadata(extension: vscode.Extension<unknown>): string {
  const packageJSON = extension.packageJSON as Record<string, unknown> | undefined;

  return [
    extension.id,
    stringMetadata(packageJSON?.displayName),
    stringMetadata(packageJSON?.description),
    stringMetadata(packageJSON?.publisher),
    stringMetadata(packageJSON?.name)
  ]
    .join(' ')
    .toLowerCase();
}

function stringMetadata(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function describePhoenixLSExpertDetection(mode: PhoenixLSModeResolution): string {
  if (!mode.detectExpert) {
    return 'companion detection disabled';
  }

  if (mode.detectedExpert) {
    return 'Expert detected';
  }

  if (mode.detectedGenericElixirLS) {
    return 'ElixirLS detected';
  }

  return 'no companion peer detected';
}

export async function activate(context: vscode.ExtensionContext) {
  try {
    // CRITICAL: Log to Developer Tools console FIRST (before anything else)
    console.log('======================================');
    console.log('PHOENIX LSP ACTIVATION STARTED');
    console.log('======================================');

    const outputChannel = vscode.window.createOutputChannel('Phoenix Pulse');
    console.log('Output channel created');

    outputChannel.appendLine('Phoenix Pulse extension activating...');
    console.log('Phoenix Pulse extension is now active!');
    outputChannel.appendLine('Starting Elixir language server; project detection runs in the server.');
    registerEmbeddedLanguageForwarding(context, outputChannel);

    try {
      const resolvedServer = resolveServer(context, outputChannel);

      if (!resolvedServer) {
        vscode.window.showErrorMessage('Phoenix LS executable not found. Configure phoenixPulse.serverPath.');
        return;
      }

      outputChannel.appendLine(`Phoenix LS executable path: ${resolvedServer.command}`);
      console.log(`Phoenix LS executable path: ${resolvedServer.command}`);
      const phoenixLSMode = resolvePhoenixLSMode();
      outputChannel.appendLine(describePhoenixLSMode(phoenixLSMode));

      // Server options - run the Elixir LSP executable using stdio
      const serverOptions = buildPhoenixLSServerOptions(resolvedServer, phoenixLSMode);

    // Client options - configure which files the LSP should handle
    const clientOptions: LanguageClientOptions = {
      // Register the server for HEEx and Elixir files (with pattern fallbacks)
      documentSelector: [
        { scheme: 'file', language: 'phoenix-heex' },
        { scheme: 'file', language: 'elixir' },
        { scheme: 'file', pattern: '**/*.heex' },  // Fallback for .heex files
        { scheme: 'file', pattern: '**/*.ex' },    // Fallback for .ex files
        { scheme: 'file', pattern: '**/*.exs' }    // Fallback for .exs files
      ],
      synchronize: {
        // Notify the server about file changes to Elixir files and static assets
        fileEvents: vscode.workspace.createFileSystemWatcher(
          '**/*.{ex,exs,heex,png,jpg,jpeg,gif,svg,webp,ico,bmp,css,scss,sass,less,js,mjs,jsx,ts,tsx,woff,woff2,ttf,otf,eot}',
          false,  // ignoreCreateEvents - watch for new file creations
          false,  // ignoreChangeEvents - watch for file modifications
          false   // ignoreDeleteEvents - watch for file deletions
        )
      },
      outputChannel: outputChannel
    };

    // Create the language client and start it
    client = new LanguageClient(
      'phoenixLSP',
      'Phoenix Pulse',
      serverOptions,
      clientOptions
    );

    // Handle client errors
    client.onDidChangeState((event) => {
      outputChannel.appendLine(`LSP State changed: ${JSON.stringify(event)}`);
    });

    // Start the client (this will also launch the server)
    outputChannel.appendLine('Starting Phoenix Pulse LSP client...');
    client.start().then(() => {
      outputChannel.appendLine('Phoenix Pulse LSP client started successfully!');
      vscode.window.showInformationMessage('Phoenix Pulse is now active!');

      clientReady =
        typeof (client as unknown as { onReady?: () => Promise<void> }).onReady === 'function'
          ? (client as unknown as { onReady: () => Promise<void> }).onReady()
          : Promise.resolve();

      clientReady.then(() => {
        // Register Tree View Provider
        const treeProvider = new PhoenixPulseTreeProvider(client);
        const treeView = vscode.window.createTreeView('phoenixPulseExplorer', {
          treeDataProvider: treeProvider
        });
        context.subscriptions.push(treeView);

        void maybeWriteDogfoodSnapshot(client, outputChannel).catch(error => {
          outputChannel.appendLine(`[Phoenix Pulse] Dogfood custom request snapshot failed: ${error}`);
        });

        // Register refresh command
        const refreshCommand = vscode.commands.registerCommand('phoenixPulse.refreshExplorer', () => {
          const hadSearch = treeProvider.getSearchQuery() !== '';
          outputChannel.appendLine('Refreshing Phoenix Pulse Explorer...');
          treeProvider.refresh();
          if (hadSearch) {
            vscode.window.showInformationMessage('Refreshed (search cleared)');
          }
        });
        context.subscriptions.push(refreshCommand);

        // Register go to item command
        const goToItemCommand = vscode.commands.registerCommand(
          'phoenixPulse.goToItem',
          async (filePath: string, location: { line: number; character: number }) => {
            try {
              // Strip fragment identifier from filePath (e.g., "/path/file.ex#function_name" -> "/path/file.ex")
              // Function templates may include fragments to distinguish between multiple functions in same file
              const cleanFilePath = filePath.split('#')[0];

              const uri = vscode.Uri.file(cleanFilePath);
              const document = await vscode.workspace.openTextDocument(uri);
              const editor = await vscode.window.showTextDocument(document);

              const position = new vscode.Position(location.line, location.character);
              editor.selection = new vscode.Selection(position, position);
              editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
            } catch (error) {
              outputChannel.appendLine(`[Phoenix Pulse] Failed to navigate to item: ${error}`);
              vscode.window.showErrorMessage(`Failed to open file: ${filePath}`);
            }
          }
        );
        context.subscriptions.push(goToItemCommand);

        // Register copy commands
        const copyNameCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyName',
          (item: any) => {
            const name = copyNameForItem(item);

            if (name) {
              vscode.env.clipboard.writeText(name);
              vscode.window.showInformationMessage(`Copied: ${name}`);
            }
          }
        );
        context.subscriptions.push(copyNameCommand);

        const copyModuleNameCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyModuleName',
          (item: any) => {
            if (!item || !item.data) return;

            const moduleName = copyModuleForItem(item);

            if (moduleName) {
              vscode.env.clipboard.writeText(moduleName);
              vscode.window.showInformationMessage(`Copied module: ${moduleName}`);
            }
          }
        );
        context.subscriptions.push(copyModuleNameCommand);

        const copyFilePathCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyFilePath',
          (item: any) => {
            if (!item || !item.data) return;

            let filePath = '';

            // Direct file path from data
            if (item.data.filePath) {
              filePath = item.data.filePath;
            }
            // For file nodes, might need tooltip
            else if (item.tooltip && typeof item.tooltip === 'string') {
              const lines = item.tooltip.split('\n');
              filePath = lines[lines.length - 1];
            }

            if (filePath) {
              vscode.env.clipboard.writeText(filePath);
              vscode.window.showInformationMessage(`Copied path: ${filePath}`);
            }
          }
        );
        context.subscriptions.push(copyFilePathCommand);

        const copyRoutePathCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyRoutePath',
          (item: any) => {
            const routePath = item?.data?.path;

            if (routePath) {
              vscode.env.clipboard.writeText(routePath);
              vscode.window.showInformationMessage(`Copied route: ${routePath}`);
            }
          }
        );
        context.subscriptions.push(copyRoutePathCommand);

        const copyComponentTagCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyComponentTag',
          (item: any) => {
            if (item && item.label) {
              const tag = `<.${item.label}>`;
              vscode.env.clipboard.writeText(tag);
              vscode.window.showInformationMessage(`Copied tag: ${tag}`);
            }
          }
        );
        context.subscriptions.push(copyComponentTagCommand);

        const copyTableNameCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyTableName',
          (item: any) => {
            const tableName = item?.data?.tableName || item?.data?.table;

            if (tableName) {
              vscode.env.clipboard.writeText(tableName);
              vscode.window.showInformationMessage(`Copied table: ${tableName}`);
            }
          }
        );
        context.subscriptions.push(copyTableNameCommand);

        // Register search commands
        const searchExplorerCommand = vscode.commands.registerCommand(
          'phoenixPulse.searchExplorer',
          async () => {
            const query = await vscode.window.showInputBox({
              prompt: 'Search Phoenix Pulse Explorer (searches names, paths, actions, etc.)',
              placeHolder: 'e.g. "user", "POST", "/api", "button"',
              value: treeProvider.getSearchQuery()
            });

            if (query !== undefined) {
              if (query) {
                outputChannel.appendLine(`[Phoenix Pulse] Searching for: "${query}"`);
                treeProvider.setSearchQuery(query);
                vscode.window.showInformationMessage(`Filtering by: "${query}" (check tree below)`);
              } else {
                // Empty string = clear search
                treeProvider.clearSearch();
                vscode.window.showInformationMessage('Search cleared');
              }
            }
          }
        );
        context.subscriptions.push(searchExplorerCommand);

        const clearSearchCommand = vscode.commands.registerCommand(
          'phoenixPulse.clearSearch',
          () => {
            treeProvider.clearSearch();
            vscode.window.showInformationMessage('Search cleared');
          }
        );
        context.subscriptions.push(clearSearchCommand);

        // Register collapse all command
        const collapseAllCommand = vscode.commands.registerCommand(
          'phoenixPulse.collapseAll',
          async () => {
            // Use VS Code's built-in collapse command
            await vscode.commands.executeCommand('workbench.actions.treeView.phoenixPulseExplorer.collapseAll');
          }
        );
        context.subscriptions.push(collapseAllCommand);

        // Register ERD diagram command
        const showErdCommand = vscode.commands.registerCommand(
          'phoenixPulse.showERD',
          async () => {
            await ErdProvider.show(context, client);
          }
        );
        context.subscriptions.push(showErdCommand);

        outputChannel.appendLine('Phoenix Pulse Explorer registered successfully!');
      }).catch((readyError) => {
        outputChannel.appendLine(`[Phoenix Pulse] Client failed to become ready: ${readyError}`);
      });
    }).catch((error) => {
      const errorMsg = `Failed to start Phoenix Pulse LSP client: ${error}`;
      outputChannel.appendLine(errorMsg);
      vscode.window.showErrorMessage(errorMsg);
    });

    console.log('Phoenix LiveView LSP client started');
    } catch (error) {
      const errorMsg = `Error activating Phoenix Pulse: ${error}`;
      outputChannel.appendLine(errorMsg);
      vscode.window.showErrorMessage(errorMsg);
      console.error('INNER ERROR:', error);
    }
  } catch (topError) {
    // Top-level catch - even if outputChannel fails
    console.error('======================================');
    console.error('CRITICAL ERROR IN PHOENIX LSP ACTIVATION');
    console.error(topError);
    console.error('======================================');
    vscode.window.showErrorMessage(`Phoenix Pulse activation failed: ${topError}`);
  }
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  console.log('Stopping Phoenix Pulse LSP client');
  return client.stop();
}

function copyNameForItem(item: any): string {
  const data = item?.data || {};

  return firstString(
    data.copyName,
    data.name,
    data.module,
    data.fieldName,
    data.path,
    data.template,
    data.layout,
    item?.label
  );
}

function copyModuleForItem(item: any): string {
  const data = item?.data || {};

  return firstString(
    data.module,
    data.controller?.module,
    data.controller,
    data.liveModule,
    data.targetModule
  );
}

function firstString(...values: unknown[]): string {
  for (const value of values) {
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }

  return '';
}

function sanitizeDefinition(
  definition: vscode.Location | vscode.LocationLink
): vscode.Location | vscode.LocationLink | null {
  const candidate = definition as any;

  // Location result
  if ('uri' in candidate && 'range' in candidate) {
    const uri = sanitizeUri(candidate.uri);
    const range = sanitizeRange(candidate.range);
    if (!uri || !range) {
      return null;
    }
    return new vscode.Location(uri, range);
  }

  // LocationLink result
  if ('targetUri' in candidate) {
    const targetUri = sanitizeUri(candidate.targetUri);
    const targetSelectionRange = sanitizeRange(candidate.targetSelectionRange ?? candidate.targetRange);
    const targetRange = sanitizeRange(candidate.targetRange) ?? targetSelectionRange;
    if (!targetUri || !targetSelectionRange || !targetRange) {
      return null;
    }

    const originSelectionRange = sanitizeRange(candidate.originSelectionRange);
    return {
      originSelectionRange,
      targetUri,
      targetRange,
      targetSelectionRange,
    };
  }

  return null;
}

function sanitizeRange(range?: vscode.Range): vscode.Range | undefined {
  if (!range) {
    return undefined;
  }

  const startLine = safeNumber((range as any).start?.line);
  const startChar = safeNumber((range as any).start?.character);
  const endLine = safeNumber((range as any).end?.line, startLine);
  const endChar = safeNumber((range as any).end?.character, startChar);

  if (Number.isNaN(startLine) || Number.isNaN(endLine)) {
    return undefined;
  }

  const start = new vscode.Position(Math.max(0, startLine), Math.max(0, startChar));
  const end = new vscode.Position(Math.max(start.line, endLine), Math.max(0, endChar));
  return new vscode.Range(start, end);
}

function sanitizeUri(value: unknown): vscode.Uri | null {
  if (!value) {
    return null;
  }

  if (value instanceof vscode.Uri) {
    return value;
  }

  try {
    return vscode.Uri.parse(String(value));
  } catch {
    return null;
  }
}

function safeNumber(value: unknown, fallback = 0): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (value === null || value === undefined) {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}
