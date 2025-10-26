import * as path from 'path';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
  DefinitionRequest
} from 'vscode-languageclient/node';
import { PhoenixPulseTreeProvider } from './tree-view-provider';
import { ErdProvider } from './diagrams/erd-provider';

let client: LanguageClient;
let clientReady: Promise<void> = Promise.resolve();

/**
 * Check if the current workspace is a Phoenix project
 * Looks for mix.exs and searches for {:phoenix dependency
 */
async function checkForPhoenixProject(outputChannel: vscode.OutputChannel): Promise<boolean> {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders || workspaceFolders.length === 0) {
    outputChannel.appendLine('No workspace folder found');
    return false;
  }

  const fs = require('fs');
  const workspaceRoot = workspaceFolders[0].uri.fsPath;
  const mixExsPath = path.join(workspaceRoot, 'mix.exs');

  // Check if mix.exs exists
  if (!fs.existsSync(mixExsPath)) {
    outputChannel.appendLine('mix.exs not found - not an Elixir project');
    return false;
  }

  outputChannel.appendLine('mix.exs found - checking for Phoenix dependency...');

  try {
    // Read mix.exs and check for {:phoenix dependency
    const mixExsContent = fs.readFileSync(mixExsPath, 'utf-8');
    const hasPhoenix = /\{:phoenix\b/.test(mixExsContent);

    if (hasPhoenix) {
      outputChannel.appendLine('Phoenix dependency found in mix.exs');
      return true;
    } else {
      outputChannel.appendLine('Phoenix dependency not found - pure Elixir project');
      return false;
    }
  } catch (error) {
    outputChannel.appendLine(`Error reading mix.exs: ${error}`);
    return false;
  }
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

    // Check if this is a Phoenix project
    const isPhoenixProject = await checkForPhoenixProject(outputChannel);
    if (!isPhoenixProject) {
      outputChannel.appendLine('ℹ️ Phoenix Pulse works best with Phoenix projects.');
      outputChannel.appendLine('Continuing activation for Elixir support...');
    } else {
      outputChannel.appendLine('✅ Phoenix project detected!');
    }

    try {
    // Path to the language server module
    // Try multiple resolution strategies
    let serverModule: string;
    try {
      // Try to require.resolve from node_modules (workspace link during development)
      serverModule = require.resolve('@phoenix-pulse/language-server');
    } catch (e) {
      // Fallback 1: Bundled LSP in extension (production)
      const bundledPath = context.asAbsolutePath(path.join('lsp', 'dist', 'server.js'));
      const fs = require('fs');
      if (fs.existsSync(bundledPath)) {
        serverModule = bundledPath;
      } else {
        // Fallback 2: Monorepo development (relative to extension)
        serverModule = context.asAbsolutePath(
          path.join('..', 'language-server', 'dist', 'server.js')
        );
      }
    }

    outputChannel.appendLine(`LSP server module path: ${serverModule}`);
    console.log(`LSP server module path: ${serverModule}`);

    // Check if server module exists
    const fs = require('fs');
    if (!fs.existsSync(serverModule)) {
      const errorMsg = `ERROR: LSP server module not found at ${serverModule}`;
      outputChannel.appendLine(errorMsg);
      vscode.window.showErrorMessage(errorMsg);
      return;
    }

    // Server options - run the LSP server using Node.js IPC
    const serverOptions: ServerOptions = {
      run: { module: serverModule, transport: TransportKind.ipc },
      debug: {
        module: serverModule,
        transport: TransportKind.ipc,
        options: { execArgv: ['--nolazy', '--inspect=6009'] }
      }
    };

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
            if (item && item.label) {
              vscode.env.clipboard.writeText(item.label);
              vscode.window.showInformationMessage(`Copied: ${item.label}`);
            }
          }
        );
        context.subscriptions.push(copyNameCommand);

        const copyModuleNameCommand = vscode.commands.registerCommand(
          'phoenixPulse.copyModuleName',
          async (item: any) => {
            if (!item || !item.data) return;

            let moduleName = '';

            // For schemas: data is the schema object
            if (item.contextValue === 'schema' || item.contextValue === 'schema-expandable') {
              moduleName = item.data.name;
            }
            // For components: need to fetch from LSP
            else if (item.contextValue === 'component' || item.contextValue === 'component-expandable') {
              const components = await client.sendRequest('phoenix/listComponents', {});
              const component = components.find((c: any) => c.name === item.label);
              if (component) {
                // Extract module from filePath: /lib/my_app_web/components/core_components.ex
                const match = component.filePath.match(/lib\/(.+)\.ex$/);
                if (match) {
                  moduleName = match[1]
                    .split('/')
                    .map((part: string) =>
                      part.split('_').map((w: string) =>
                        w.charAt(0).toUpperCase() + w.slice(1)
                      ).join('')
                    )
                    .join('.');
                }
              }
            }

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
            if (item && item.label) {
              // Extract path from label "GET /users/:id"
              const match = item.label.match(/^[A-Z]+\s+(.+)$/);
              if (match) {
                const routePath = match[1];
                vscode.env.clipboard.writeText(routePath);
                vscode.window.showInformationMessage(`Copied route: ${routePath}`);
              }
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
            if (item && item.data && item.data.tableName) {
              vscode.env.clipboard.writeText(item.data.tableName);
              vscode.window.showInformationMessage(`Copied table: ${item.data.tableName}`);
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
