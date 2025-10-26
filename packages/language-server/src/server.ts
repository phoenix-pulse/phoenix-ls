import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  CompletionItem,
  CompletionItemKind,
  CompletionList,
  Definition,
  DefinitionLink,
  Location,
  Position,
  Range,
  TextDocumentPositionParams,
  TextDocumentSyncKind,
  InitializeResult,
  Hover,
  MarkupKind,
  Diagnostic,
  DiagnosticSeverity,
  SignatureHelp,
  SignatureInformation,
  ParameterInformation,
  CodeAction,
  CodeActionKind,
  CodeActionParams,
  WorkspaceEdit,
  TextEdit,
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { getPhoenixCompletions, getPhoenixAttributeDocumentation, getContextAwarePhxValueCompletions } from './completions/phoenix';
import { getSmartHtmlCompletions, getHtmlAttributeValueCompletions } from './completions/html-smart';
import { getPhoenixSnippetCompletions } from './completions/phoenix-snippets';
import { getElementContext } from './utils/element-context';
import { getEmmetCompletions } from './completions/emmet';
import {
  getJSCommandCompletions,
  getChainableJSCompletions,
  isJSCommandContext,
  isPipeChainContext
} from './completions/js-commands';
import { EventsRegistry } from './events-registry';
import type { PhoenixEvent } from './events-registry';
import { LiveViewRegistry } from './liveview-registry';
import { ComponentsRegistry, PhoenixComponent, ComponentSlot, getAttributeTypeDisplay } from './components-registry';
import { SchemaRegistry } from './schema-registry';
import {
  getLocalComponentCompletions,
  getComponentAttributeCompletions,
  getComponentSlotCompletions,
  isLocalComponentContext,
  getComponentNameFromContext,
  getModuleNameFromContext,
  buildComponentHoverDocumentation,
  buildAttributeHoverDocumentation,
} from './completions/components';
import {
  getAssignCompletions,
  isAtSignContext,
  isAssignsContext,
  isForLoopVariableContext,
} from './completions/assigns';
import { getSpecialAttributeCompletions } from './completions/special-attributes';
import { validatePhoenixAttributes, getUnusedEventDiagnostics, validateForLoopKeys } from './validators/phoenix-diagnostics';
import { validateComponentUsage } from './validators/component-diagnostics';
import { validateNavigationComponents, validateJsPushUsage } from './validators/navigation-diagnostics';
import { validateStreams } from './validators/stream-diagnostics';
import { validateRoutes } from './validators/route-diagnostics';
import { validateTemplates } from './validators/template-diagnostics';
import { getFormFieldCompletions } from './completions/form-fields';
import { getRouteHelperCompletions, getVerifiedRouteCompletions } from './completions/routes';
import { RouterRegistry } from './router-registry';
import { AssetRegistry } from './asset-registry';
import { getAssetCompletions } from './completions/assets';
import { getHandleInfoEventCompletions } from './completions/events';
import { getTemplateCompletions } from './completions/templates';
import * as fs from 'fs';
import * as path from 'path';
import { URI } from 'vscode-uri';
import {
  initializeTreeSitter,
  isTreeSitterReady,
  getTreeSitterError,
  getTreeCacheKeys,
  getHeexTree,
  clearTreeCache,
} from './parsers/tree-sitter';
import { TemplatesRegistry } from './templates-registry';
import { ControllersRegistry } from './controllers-registry';
import { CacheManager } from './utils/cache-manager';
import { filterDiagnosticsInsideComments } from './utils/comments';
import { getComponentUsageStack, getComponentUsageStackAsync, ComponentUsage } from './utils/component-usage';
import { PerfTimer } from './utils/perf';

// Create a connection for the server
const connection = createConnection(ProposedFeatures.all);

const debugFlagString = process.env.PHOENIX_PULSE_DEBUG ?? '';
const debugFlags = new Set(
  debugFlagString
    .split(',')
    .map(flag => flag.trim().toLowerCase())
    .filter(Boolean)
);

const definitionCache = new Map<string, Location>();
const DEFINITION_CACHE_LIMIT = 200;

function cacheDefinition(key: string, location: Location) {
  if (definitionCache.has(key)) {
    definitionCache.set(key, location);
    return;
  }
  if (definitionCache.size >= DEFINITION_CACHE_LIMIT) {
    const firstKey = definitionCache.keys().next().value;
    if (firstKey) {
      definitionCache.delete(firstKey);
    }
  }
  definitionCache.set(key, location);
}

function getCachedDefinition(key: string): Location | null {
  return definitionCache.get(key) || null;
}

// File content cache for definition requests (LRU with 50 file limit)
const fileContentCache = new Map<string, string>();
const FILE_CONTENT_CACHE_LIMIT = 50;

function getCachedFileContent(filePath: string): string | null {
  return fileContentCache.get(filePath) || null;
}

function cacheFileContent(filePath: string, content: string) {
  // If already in cache, delete and re-add to move to end (LRU)
  if (fileContentCache.has(filePath)) {
    fileContentCache.delete(filePath);
  }
  // Evict oldest entry if at limit
  if (fileContentCache.size >= FILE_CONTENT_CACHE_LIMIT) {
    const firstKey = fileContentCache.keys().next().value;
    if (firstKey) {
      fileContentCache.delete(firstKey);
    }
  }
  fileContentCache.set(filePath, content);
}

function clearFileContentCache(filePath: string) {
  fileContentCache.delete(filePath);
}

function clearDefinitionCacheForFile(filePath: string) {
  const keysToDelete: string[] = [];
  definitionCache.forEach((_, key) => {
    if (key.startsWith(`${filePath}:`)) {
      keysToDelete.push(key);
    }
  });
  keysToDelete.forEach(key => definitionCache.delete(key));
}

function clearDefinitionCacheReferencingTarget(targetFilePath: string) {
  const targetUri = URI.file(targetFilePath).toString();
  const keysToDelete: string[] = [];
  definitionCache.forEach((location, key) => {
    if (location.uri === targetUri) {
      keysToDelete.push(key);
    }
  });
  keysToDelete.forEach(key => definitionCache.delete(key));
}

function debugLog(flag: string, message: string) {
  if (debugFlags.has('all') || debugFlags.has(flag)) {
    connection.console.log(`[debug:${flag}] ${message}`);
  }
}

connection.console.log(
  debugFlags.size > 0
    ? `[Phoenix Pulse] Debug flags enabled: ${Array.from(debugFlags).join(', ')}`
    : '[Phoenix Pulse] Debug flags disabled (set PHOENIX_PULSE_DEBUG to enable)'
);

// Create a simple text document manager
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

// Create events registry
const eventsRegistry = new EventsRegistry();

// Create LiveView registry
const liveViewRegistry = new LiveViewRegistry();

// Create components registry
const componentsRegistry = new ComponentsRegistry();

// Create schema registry
const schemaRegistry = new SchemaRegistry();

// Create router registry
const routerRegistry = new RouterRegistry();

// Create asset registry
const assetRegistry = new AssetRegistry();

// Create template registry
const templatesRegistry = new TemplatesRegistry();

// Create controller registry
const controllersRegistry = new ControllersRegistry(templatesRegistry);

connection.onInitialize((params: InitializeParams) => {
  const result: InitializeResult = {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: {
        resolveProvider: true,
        triggerCharacters: ['<', ' ', '-', ':', '"', '=', '{', '.', '#', '@'],
      },
      hoverProvider: true,
      definitionProvider: true,
      signatureHelpProvider: {
        triggerCharacters: ['<', ' '],
        retriggerCharacters: [' '],
      },
      codeActionProvider: {
        codeActionKinds: [
          'quickfix',
        ],
      },
      // Using push diagnostics (connection.sendDiagnostics) instead of pull diagnostics
    },
  };
  return result;
});

connection.onInitialized(async () => {
  connection.console.log('Phoenix LiveView LSP initialized!');

  const workspaceFolders = await connection.workspace.getWorkspaceFolders();
  if (workspaceFolders && workspaceFolders.length > 0) {
    const workspaceRoot = URI.parse(workspaceFolders[0].uri).fsPath;

    // Track scan start time
    const scanStartTime = Date.now();

    // Create progress token for scanning
    const progressToken = 'phoenix-pulse-scan-' + Date.now();
    let supportsProgress = true;

    try {
      await connection.sendRequest('window/workDoneProgress/create', { token: progressToken });

      // Start progress notification
      connection.sendNotification('$/progress', {
        token: progressToken,
        value: {
          kind: 'begin',
          title: 'Phoenix Pulse',
          message: 'Scanning workspace...',
          cancellable: false
        }
      });
    } catch (err) {
      // Client doesn't support work done progress, use fallback
      supportsProgress = false;
      connection.console.log('[Phoenix Pulse] Starting workspace scan...');
    }

    // Set workspace roots for all registries
    componentsRegistry.setWorkspaceRoot(workspaceRoot);
    templatesRegistry.setWorkspaceRoot(workspaceRoot);
    controllersRegistry.setWorkspaceRoot(workspaceRoot);
    liveViewRegistry.setWorkspaceRoot(workspaceRoot);

    // Try to load from cache first
    let cacheLoaded = false;
    try {
      const cache = await CacheManager.loadCache(workspaceRoot);

      if (cache) {
        // Collect all files for validation
        const filesToCheck = CacheManager.collectFilesForValidation(workspaceRoot);

        // Validate cache freshness
        const isFresh = await CacheManager.validateCacheFreshness(workspaceRoot, cache, filesToCheck);

        if (isFresh && cache.registries) {
          // Load all registries from cache
          connection.console.log('[Phoenix Pulse] Loading from cache...');

          if (cache.registries.components) {
            componentsRegistry.loadFromCache(cache.registries.components);
          }
          if (cache.registries.schemas) {
            schemaRegistry.loadFromCache(cache.registries.schemas);
          }
          if (cache.registries.events) {
            eventsRegistry.loadFromCache(cache.registries.events);
          }
          if (cache.registries.routes) {
            routerRegistry.loadFromCache(cache.registries.routes);
          }
          if (cache.registries.controllers) {
            controllersRegistry.loadFromCache(cache.registries.controllers);
          }
          if (cache.registries.templates) {
            templatesRegistry.loadFromCache(cache.registries.templates);
          }
          if (cache.registries.liveview) {
            liveViewRegistry.loadFromCache(cache.registries.liveview);
          }

          cacheLoaded = true;
          connection.console.log('[Phoenix Pulse] Cache loaded successfully');

          // Update progress to show cache loading
          if (supportsProgress) {
            connection.sendNotification('$/progress', {
              token: progressToken,
              value: {
                kind: 'report',
                message: 'Loading from cache...',
                percentage: 50
              }
            });
          }
        }
      }
    } catch (error) {
      connection.console.log(`[Phoenix Pulse] Cache loading failed: ${error instanceof Error ? error.message : String(error)}`);
    }

    // Scan all registries in parallel for faster startup (or use cached data)
    let completedRegistries = 0;
    const totalRegistries = 8;

    const sendProgress = (registryName: string) => {
      completedRegistries++;
      const percentage = Math.round((completedRegistries / totalRegistries) * 100);
      if (supportsProgress) {
        connection.sendNotification('$/progress', {
          token: progressToken,
          value: {
            kind: 'report',
            message: cacheLoaded ? 'Loading from cache...' : `Scanning... (${completedRegistries}/${totalRegistries})`,
            percentage
          }
        });
      }
    };

    let eventsResult, liveViewResult, componentsResult, schemasResult, routesResult, assetsResult, templatesResult, controllersResult;

    if (cacheLoaded) {
      // Use cached data - skip scanning (except assets which isn't cached)
      connection.console.log('[Phoenix Pulse] Using cached registry data');
      eventsResult = { name: 'events', count: eventsRegistry.getAllEvents().length, time: 0 };
      const liveViewModules = liveViewRegistry.getAllModules();
      liveViewResult = { name: 'liveview', count: liveViewModules.reduce((sum, m) => sum + m.functions.length, 0), modules: liveViewModules.length, time: 0 };
      componentsResult = { name: 'components', count: componentsRegistry.getAllComponents().length, time: 0 };
      schemasResult = { name: 'schemas', count: schemaRegistry.getAllSchemas().length, time: 0 };
      routesResult = { name: 'routes', count: routerRegistry.getRoutes().length, time: 0 };
      templatesResult = { name: 'templates', count: templatesRegistry.getAllTemplates().length, time: 0 };
      let totalRenders = 0;
      controllersRegistry['rendersByFile'].forEach((renders: any) => {
        totalRenders += renders.length;
      });
      controllersResult = { name: 'controllers', count: totalRenders, time: 0 };

      // Still need to scan assets (not cached)
      const assetStart = Date.now();
      assetRegistry.scanWorkspace(workspaceRoot);
      assetsResult = { name: 'assets', count: assetRegistry.getAssets().length, time: Date.now() - assetStart };
    } else {
      // Perform full workspace scan
      [eventsResult, liveViewResult, componentsResult, schemasResult, routesResult, assetsResult, templatesResult, controllersResult] = await Promise.all([
      // Events
      (async () => {
        const start = Date.now();
        await eventsRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = eventsRegistry.getAllEvents().length;
        sendProgress('events');
        return { name: 'events', count, time };
      })(),
      // LiveView
      (async () => {
        const start = Date.now();
        await liveViewRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const modules = liveViewRegistry.getAllModules();
        const count = modules.reduce((sum, m) => sum + m.functions.length, 0);
        sendProgress('liveview');
        return { name: 'liveview', count, modules: modules.length, time };
      })(),
      // Components
      (async () => {
        const start = Date.now();
        await componentsRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = componentsRegistry.getAllComponents().length;
        sendProgress('components');
        return { name: 'components', count, time };
      })(),
      // Schemas
      (async () => {
        const start = Date.now();
        await schemaRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = schemaRegistry.getAllSchemas().length;
        sendProgress('schemas');
        return { name: 'schemas', count, time };
      })(),
      // Routes
      (async () => {
        const start = Date.now();
        await routerRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = routerRegistry.getRoutes().length;
        sendProgress('routes');
        return { name: 'routes', count, time };
      })(),
      // Assets
      (async () => {
        const start = Date.now();
        assetRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = assetRegistry.getAssets().length;
        sendProgress('assets');
        return { name: 'assets', count, time };
      })(),
      // Templates
      (async () => {
        const start = Date.now();
        await templatesRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        const count = templatesRegistry.getAllTemplates().length;
        sendProgress('templates');
        return { name: 'templates', count, time };
      })(),
      // Controllers
      (async () => {
        const start = Date.now();
        await controllersRegistry.scanWorkspace(workspaceRoot);
        const time = Date.now() - start;
        // Count total render() calls across all controller files
        let totalRenders = 0;
        controllersRegistry['rendersByFile'].forEach(renders => {
          totalRenders += renders.length;
        });
        sendProgress('controllers');
        return { name: 'controllers', count: totalRenders, time };
      })(),
      ]);

      // Save cache after successful scan
      try {
        await CacheManager.saveCache(workspaceRoot, {
          version: '1.2.2',
          timestamp: Date.now(),
          workspaceRoot,
          registries: {
            components: componentsRegistry.serializeForCache(),
            schemas: schemaRegistry.serializeForCache(),
            events: eventsRegistry.serializeForCache(),
            routes: routerRegistry.serializeForCache(),
            controllers: controllersRegistry.serializeForCache(),
            templates: templatesRegistry.serializeForCache(),
            liveview: liveViewRegistry.serializeForCache(),
          },
          fileHashes: {},
        });
      } catch (error) {
        connection.console.log(`[Phoenix Pulse] Failed to save cache: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Log individual registry scan times
    connection.console.log(`[Phoenix Pulse] Found ${eventsResult.count} events in ${eventsResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${liveViewResult.modules} LiveView modules (${liveViewResult.count} functions) in ${liveViewResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${componentsResult.count} components in ${componentsResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${schemasResult.count} schemas in ${schemasResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${routesResult.count} routes in ${routesResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${assetsResult.count} assets in ${assetsResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${templatesResult.count} templates in ${templatesResult.time}ms`);
    connection.console.log(`[Phoenix Pulse] Found ${controllersResult.count} render() calls in ${controllersResult.time}ms`);

    const totalScanTime = Date.now() - scanStartTime;

    // Show completion notification with summary
    const componentCount = componentsRegistry.getAllComponents().length;
    const routeCount = routerRegistry.getRoutes().length;
    const eventCount = eventsRegistry.getAllEvents().length;
    const schemaCount = schemaRegistry.getAllSchemas().length;
    const templateCount = templatesResult.count;
    const controllerCount = controllersResult.count;

    // End progress notification
    const cacheStatus = cacheLoaded ? ' (from cache)' : '';
    if (supportsProgress) {
      connection.sendNotification('$/progress', {
        token: progressToken,
        value: {
          kind: 'end',
          message: `Ready! ${componentCount} components, ${routeCount} routes, ${schemaCount} schemas indexed in ${totalScanTime}ms${cacheStatus}`
        }
      });
    }

    // Log detailed summary to console
    connection.console.log(`[Phoenix Pulse] Workspace ${cacheLoaded ? 'loaded from cache' : 'scan complete'} in ${totalScanTime}ms`);
    connection.console.log(`[Phoenix Pulse] Summary: ${componentCount} components, ${routeCount} routes, ${schemaCount} schemas, ${eventCount} events, ${templateCount} templates, ${controllerCount} render() calls`);

    // Check if Elixir is available and show helpful message if not
    const { isElixirAvailable } = await import('./parsers/elixir-ast-parser');
    const elixirAvailable = await isElixirAvailable();
    if (!elixirAvailable) {
      connection.sendNotification('window/showMessage', {
        type: 2, // Warning
        message: 'Phoenix Pulse: Elixir not found. Install Elixir for 100% accurate parsing or the extension will use regex fallback.'
      });
      connection.console.log('[Phoenix Pulse] WARNING: Elixir not installed. Using regex parser as fallback.');
      connection.console.log('[Phoenix Pulse] For best results, install Elixir: https://elixir-lang.org/install.html');
    }

    // Initialize Tree-sitter (optional - falls back to regex parsing)
    await initializeTreeSitter(workspaceRoot);
    // Note: Tree-sitter is currently disabled due to WASM compatibility issues
    // Extension uses regex parsing as fallback (works well)
  }
});

// Debounce map for file updates (prevents updating on every keystroke)
const updateDebounceTimers = new Map<string, NodeJS.Timeout>();
const DEBOUNCE_DELAY = 500; // ms - wait 500ms after last keystroke

// Watch for file changes to update event registry and components registry
documents.onDidChangeContent(async (change) => {
  const doc = change.document;
  const uri = doc.uri;
  const filePath = URI.parse(uri).fsPath;
  const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');
  const isHeexFile = uri.endsWith('.heex');

  // Clear existing timer for this file
  const existingTimer = updateDebounceTimers.get(filePath);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }

  // Set new timer - actual update will happen after DEBOUNCE_DELAY
  const timer = setTimeout(async () => {
    updateDebounceTimers.delete(filePath);

    const content = doc.getText();

    // Process .ex and .exs files for event, component, and schema registries
    if (isElixirFile) {
      await templatesRegistry.updateFile(filePath, content);
      await eventsRegistry.updateFile(filePath, content);
      await componentsRegistry.updateFileAsync(filePath, content);
      // Update LiveView registry if file is a LiveView file
      // LiveView files are either:
      // 1. Files ending with *_live.ex
      // 2. .ex files inside folders ending with _live/
      const isLiveViewFile = filePath.endsWith('_live.ex');
      const parentDirName = path.basename(path.dirname(filePath));
      const isInLiveFolder = parentDirName.endsWith('_live');

      if (isLiveViewFile || isInLiveFolder) {
        await liveViewRegistry.updateFile(filePath, content);
      }
      // Update schema registry if file contains schema definition
      if (content.includes('schema ') || content.includes('embedded_schema')) {
        await schemaRegistry.updateFileAsync(filePath, content);
      }
      if (filePath.includes('router.ex')) {
        await routerRegistry.updateFile(filePath, content);
      }
      if (filePath.endsWith('_controller.ex')) {
        await controllersRegistry.updateFile(filePath, content);
      } else {
        controllersRegistry.refreshTemplateSummaries();
      }
    }

    if (isHeexFile) {
      updateHeexTreesForHeexDocument(filePath, content);
    } else if (isElixirFile) {
      if (content.includes('~H')) {
        updateHeexTreesForElixirDocument(filePath, content);
      } else {
        pruneHeexTreeCache(filePath, new Set());
      }
    }

    // Validate .heex files and .ex/.exs files (with ~H sigils)
    if (isHeexFile || isElixirFile) {
      validateDocument(doc);
    }

    if (isElixirFile || isHeexFile) {
      clearDefinitionCacheForFile(filePath);
      clearDefinitionCacheReferencingTarget(filePath);
      clearFileContentCache(filePath);
    }
  }, DEBOUNCE_DELAY);

  // Store timer so it can be cleared if user types again
  updateDebounceTimers.set(filePath, timer);
});

documents.onDidOpen(async (e) => {
  const doc = e.document;
  const uri = doc.uri;
  const filePath = URI.parse(uri).fsPath;
  const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');
  const isHeexFile = uri.endsWith('.heex');
  const content = doc.getText();

  // Update registries on open (same as onDidChangeContent)
  // This ensures completions work immediately when opening a file
  if (isElixirFile) {
    await templatesRegistry.updateFile(filePath, content);
    await eventsRegistry.updateFile(filePath, content);
    await componentsRegistry.updateFileAsync(filePath, content);
    // Update schema registry if file contains schema definition
    if (content.includes('schema ') || content.includes('embedded_schema')) {
      await schemaRegistry.updateFileAsync(filePath, content);
    }
    if (filePath.includes('router.ex')) {
      connection.console.log(`[onDidOpen] Router file opened: ${filePath}`);
      const routesBefore = routerRegistry.getRoutes().length;
      await routerRegistry.updateFile(filePath, content);
      const routesAfter = routerRegistry.getRoutes().length;
      connection.console.log(`[onDidOpen] Routes before: ${routesBefore}, after: ${routesAfter}`);
    }
    if (filePath.endsWith('_controller.ex')) {
      await controllersRegistry.updateFile(filePath, content);
    } else {
      controllersRegistry.refreshTemplateSummaries();
    }
  }

  if (isHeexFile) {
    updateHeexTreesForHeexDocument(filePath, content);
  } else if (isElixirFile) {
    if (content.includes('~H')) {
      updateHeexTreesForElixirDocument(filePath, content);
    }
  }

  // Validate on open for .heex and .ex/.exs files
  if (isHeexFile || isElixirFile) {
    validateDocument(doc);
  }
});

documents.onDidClose((e) => {
  const uri = e.document.uri;
  const filePath = URI.parse(uri).fsPath;

  // IMPORTANT: Do NOT remove files from registries on close!
  // The file still exists on disk and other files may reference it.
  // Registries should reflect workspace state, not which files are open.
  // File watcher will handle updates when closed files change on disk.

  // Only clear caches and diagnostics (things specific to the editor state)
  if (uri.endsWith('.ex') || uri.endsWith('.exs') || uri.endsWith('.heex')) {
    clearHeexTreeCachesForFile(filePath);
    clearDefinitionCacheForFile(filePath);
    clearDefinitionCacheReferencingTarget(filePath);
    clearFileContentCache(filePath);
  }

  // Clear diagnostics when document closes
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
});

// Watch for file system changes (for files not currently open)
connection.onDidChangeWatchedFiles(async (params) => {
  for (const change of params.changes) {
    const uri = change.uri;
    const filePath = URI.parse(uri).fsPath;
    const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');
    const isHeexFile = uri.endsWith('.heex');

    // Skip if document is currently open (handled by onDidChangeContent)
    const openDoc = documents.get(uri);
    if (openDoc) {
      continue;
    }

    // File created or modified
    if (change.type === 1 || change.type === 2) {
      if (isElixirFile && fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf-8');

        await templatesRegistry.updateFile(filePath, content);
        await eventsRegistry.updateFile(filePath, content);
        await componentsRegistry.updateFileAsync(filePath, content);

        if (content.includes('schema ') || content.includes('embedded_schema')) {
          await schemaRegistry.updateFileAsync(filePath, content);
          connection.console.log(`[Phoenix Pulse] Updated schema from ${path.basename(filePath)}`);
        }

        if (filePath.includes('router.ex')) {
          await routerRegistry.updateFile(filePath, content);
          connection.console.log(`[Phoenix Pulse] Updated routes from ${path.basename(filePath)}`);
        }

        if (filePath.endsWith('_controller.ex')) {
          await controllersRegistry.updateFile(filePath, content);
          connection.console.log(`[Phoenix Pulse] Updated controller ${path.basename(filePath)}`);
        } else {
          controllersRegistry.refreshTemplateSummaries();
        }

        // Clear caches
        clearDefinitionCacheForFile(filePath);
        clearDefinitionCacheReferencingTarget(filePath);
        clearFileContentCache(filePath);
      }

      // Handle static asset files (images, css, js, fonts)
      const isAssetFile = filePath.includes('/priv/static/') || filePath.includes('\\priv\\static\\');
      if (isAssetFile) {
        assetRegistry.updateFile(filePath);
        connection.console.log(`[Phoenix Pulse] Updated asset ${path.basename(filePath)}`);
      }
    }

    // File deleted
    if (change.type === 3) {
      if (isElixirFile) {
        eventsRegistry.removeFile(filePath);
        componentsRegistry.removeFile(filePath);
        schemaRegistry.removeFile(filePath);
        routerRegistry.removeFile(filePath);
        templatesRegistry.removeFile(filePath);

        if (filePath.endsWith('_controller.ex')) {
          controllersRegistry.removeFile(filePath);
        } else {
          controllersRegistry.refreshTemplateSummaries();
        }

        connection.console.log(`[Phoenix Pulse] Removed ${path.basename(filePath)} from registries`);
      }

      if (isElixirFile || isHeexFile) {
        eventsRegistry.removeTemplateEventUsage(filePath);
        clearDefinitionCacheForFile(filePath);
        clearDefinitionCacheReferencingTarget(filePath);
        clearFileContentCache(filePath);
      }

      // Handle static asset deletion
      const isAssetFile = filePath.includes('/priv/static/') || filePath.includes('\\priv\\static\\');
      if (isAssetFile) {
        assetRegistry.removeFile(filePath);
        connection.console.log(`[Phoenix Pulse] Removed asset ${path.basename(filePath)}`);
      }
    }
  }
});

// Debounce timer for validation
let validationTimer: NodeJS.Timeout | null = null;

/**
 * Validate a document and send diagnostics
 */
function validateDocument(document: TextDocument) {
  // Debounce validation to avoid excessive checks while typing
  if (validationTimer) {
    clearTimeout(validationTimer);
  }

  validationTimer = setTimeout(() => {
    const uri = document.uri;
    const filePath = URI.parse(uri).fsPath;
    const text = document.getText();

    // Run Phoenix attribute validation
    const phoenixDiagnostics = validatePhoenixAttributes(document, eventsRegistry, filePath);
    const unusedEventDiagnostics = getUnusedEventDiagnostics(document, eventsRegistry, templatesRegistry);
    const forLoopKeyDiagnostics = validateForLoopKeys(document);
    const streamDiagnostics = validateStreams(document);

    // Run component usage validation
    const componentDiagnostics = validateComponentUsage(document, componentsRegistry, filePath);
    const navigationDiagnostics = validateNavigationComponents(document, componentsRegistry, filePath);
    const jsDiagnostics = validateJsPushUsage(document, text);

    // Run route validation
    const routeDiagnostics = validateRoutes(document, routerRegistry);

    // Run template validation (only for controllers)
    const templateDiagnostics = uri.endsWith('_controller.ex')
      ? validateTemplates(document, templatesRegistry)
      : [];

    // Combine all diagnostics
    const allDiagnostics = [
      ...phoenixDiagnostics,
      ...unusedEventDiagnostics,
      ...forLoopKeyDiagnostics,
      ...streamDiagnostics,
      ...componentDiagnostics,
      ...navigationDiagnostics,
      ...jsDiagnostics,
      ...routeDiagnostics,
      ...templateDiagnostics,
    ];

    const filteredDiagnostics = filterDiagnosticsInsideComments(document, allDiagnostics);

    // Send diagnostics to client
    connection.sendDiagnostics({ uri, diagnostics: filteredDiagnostics });
  }, 500); // 500ms debounce
}

// Helper function to check if cursor is inside a ~H sigil
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
    return false;
  }

  // Check if there's a closing delimiter between opening and cursor
  const afterOpening = text.substring(openingPos + 2 + delimiter.length, offset); // +2 for ~H
  const closingPos = afterOpening.indexOf(delimiter);

  // If no closing found, we're inside the sigil
  // If closing found, we're outside (sigil already closed)
  return closingPos === -1;
}

function getLastRegexMatch(text: string, regex: RegExp): RegExpExecArray | null {
  const flags = regex.flags.includes('g') ? regex.flags : `${regex.flags}g`;
  const globalRegex = new RegExp(regex.source, flags);
  let lastMatch: RegExpExecArray | null = null;
  let match: RegExpExecArray | null;

  while ((match = globalRegex.exec(text)) !== null) {
    lastMatch = match;
    if (globalRegex.lastIndex === match.index) {
      globalRegex.lastIndex++;
    }
  }

  return lastMatch;
}

interface ComponentUsageContext {
  componentName: string;
  moduleContext?: string;
}

function isInsideTagContext(text: string, offset: number): boolean {
  for (let i = offset - 1; i >= 0; i--) {
    const ch = text[i];
    if (ch === '>') {
      return false;
    }
    if (ch === '<') {
      if (i + 1 < text.length && text[i + 1] === '%') {
        return false;
      }
      return true;
    }
  }
  return false;
}

function findEnclosingComponentUsage(text: string, offset: number): ComponentUsageContext | null {
  const before = text.slice(0, offset);
  let pos = before.length;
  let depth = 0;

  while (pos > 0) {
    const lt = before.lastIndexOf('<', pos - 1);
    if (lt === -1) {
      break;
    }

    const gt = before.indexOf('>', lt);
    if (gt === -1 || gt >= before.length) {
      pos = lt;
      continue;
    }

    const tag = before.slice(lt, gt + 1);
    pos = lt;

    // Skip HEEx comments and slot tags
    if (tag.startsWith('<%') || tag.startsWith('<:') || tag.startsWith('</:')) {
      continue;
    }

    const localClose = tag.match(/^<\/\.([a-z_][a-z0-9_]*)\s*>$/);
    if (localClose) {
      depth++;
      continue;
    }

    const remoteClose = tag.match(/^<\/([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.([a-z_][a-z0-9_]*)\s*>$/);
    if (remoteClose) {
      depth++;
      continue;
    }

    const localOpen = tag.match(/^<\.([a-z_][a-z0-9_]*)\b[^>]*?>$/);
    if (localOpen) {
      const selfClosing = /\/>\s*$/.test(tag);
      if (selfClosing) {
        continue;
      }

      if (depth === 0) {
        return { componentName: localOpen[1] };
      }

      depth--;
      continue;
    }

    const remoteOpen = tag.match(/^<([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.([a-z_][a-z0-9_]*)\b[^>]*?>$/);
    if (remoteOpen) {
      const selfClosing = /\/>\s*$/.test(tag);
      if (selfClosing) {
        continue;
      }

      if (depth === 0) {
        return { componentName: remoteOpen[2], moduleContext: remoteOpen[1] };
      }

      depth--;
      continue;
    }
  }

  return null;
}

function isInsideJsPushEvent(linePrefix: string): boolean {
  return /JS\.push\(\s*(["'])[^"']*$/.test(linePrefix);
}

function formatEventClauseHeader(event: PhoenixEvent): string {
  const fallback = `def handle_event("${event.name}", ${event.params}, socket) do`;
  const clause = (event.clause ?? fallback).trim();
  if (/do:\s*/.test(clause)) {
    return clause.replace(/do:\s*.+$/, 'do');
  }
  if (/\bdo\b/.test(clause)) {
    return clause;
  }
  return clause.endsWith('do') ? clause : `${clause} do`;
}

function buildEventMarkdown(event: PhoenixEvent, includeHeading = true): string {
  const fileName = path.basename(event.filePath);
  const lines: string[] = [];

  if (includeHeading) {
    lines.push(`**Event \`${event.name}\`**`);
  }

  if (event.doc) {
    if (lines.length > 0) {
      lines.push('');
    }
    lines.push(event.doc.trim());
  }

  const clauseHeader = formatEventClauseHeader(event);
  if (lines.length > 0) {
    lines.push('');
  }
  lines.push('```elixir', clauseHeader, '  # ...', 'end', '```');

  const locationParts: string[] = [];
  if (event.moduleName) {
    locationParts.push(`\`${event.moduleName}\``);
  }
  locationParts.push(`\`${fileName}:${event.line}\``);
  if (lines.length > 0) {
    lines.push('');
  }
  lines.push(`Defined in ${locationParts.join(' · ')}`);
  return lines.join('\n');
}

function createEventCompletionItem(event: PhoenixEvent, sortGroup: string, index: number): CompletionItem {
  const fileName = path.basename(event.filePath);
  return {
    label: event.name,
    kind: CompletionItemKind.Event,
    detail: `handle_event · ${event.moduleName || fileName}`,
    documentation: {
      kind: MarkupKind.Markdown,
      value: buildEventMarkdown(event, false),
    },
    insertText: event.name,
    sortText: `${sortGroup}${index.toString().padStart(3, '0')}`,
  };
}

function getJsPushEventCompletions(
  filePath: string,
  eventsRegistry: EventsRegistry
): CompletionItem[] {
  const completions: CompletionItem[] = [];
  const { primary, secondary } = eventsRegistry.getEventsForTemplate(filePath);

  primary.forEach((event, index) => {
    completions.push(createEventCompletionItem(event, '0', index));
  });

  secondary.forEach((event, index) => {
    completions.push(createEventCompletionItem(event, '1', index));
  });

  return completions;
}

function createComponentLocation(component: PhoenixComponent): Location | null {
  try {
    // Check cache first, read from disk if miss
    let fileContent = getCachedFileContent(component.filePath);
    if (!fileContent) {
      fileContent = fs.readFileSync(component.filePath, 'utf-8');
      cacheFileContent(component.filePath, fileContent);
    }
    const lines = fileContent.split('\n');
    const zeroBasedLine = Math.max(0, component.line - 1);
    const lineText = lines[zeroBasedLine] ?? '';

    let startChar = lineText.indexOf(component.name);
    if (startChar === -1) {
      const defIndex = lineText.indexOf('def');
      if (defIndex !== -1) {
        startChar = defIndex;
      } else {
        const firstNonWhitespace = lineText.search(/\S/);
        startChar = firstNonWhitespace >= 0 ? firstNonWhitespace : 0;
      }
    }

    const endChar = Math.max(startChar + component.name.length, startChar);

    return {
      uri: URI.file(component.filePath).toString(),
      range: {
        start: { line: zeroBasedLine, character: startChar },
        end: { line: zeroBasedLine, character: endChar },
      },
    };
  } catch (error) {
    connection.console.error(`[Definition] Failed to create location for ${component.moduleName}.${component.name}: ${error}`);
    return null;
  }
}

function createSlotLocation(component: PhoenixComponent, slotName: string): Location | null {
  try {
    // Check cache first, read from disk if miss
    let fileContent = getCachedFileContent(component.filePath);
    if (!fileContent) {
      fileContent = fs.readFileSync(component.filePath, 'utf-8');
      cacheFileContent(component.filePath, fileContent);
    }
    const lines = fileContent.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const slotIndex = line.indexOf(`slot :${slotName}`);
      if (slotIndex !== -1) {
        return {
          uri: URI.file(component.filePath).toString(),
          range: {
            start: { line: i, character: slotIndex },
            end: { line: i, character: slotIndex + `slot :${slotName}`.length },
          },
        };
      }
    }
    return null;
  } catch (error) {
    connection.console.error(`[Definition] Failed to create slot location for ${component.moduleName}.${slotName}: ${error}`);
    return null;
  }
}

function createComponentDefinitionLink(
  document: TextDocument,
  usage: ComponentUsage,
  location: Location
): DefinitionLink {
  const originSelectionRange: Range = {
    start: document.positionAt(usage.nameStart),
    end: document.positionAt(usage.nameEnd),
  };

  return {
    originSelectionRange,
    targetUri: location.uri,
    targetRange: location.range,
    targetSelectionRange: location.range,
  };
}

function createSlotDefinitionLink(
  document: TextDocument,
  position: Position,
  charInLine: number,
  slotName: string,
  location: Location
): DefinitionLink {
  const originStart: Position = {
    line: position.line,
    character: Math.max(0, charInLine - slotName.length),
  };
  const originEnd: Position = {
    line: position.line,
    character: originStart.character + slotName.length,
  };

  return {
    originSelectionRange: {
      start: originStart,
      end: originEnd,
    },
    targetUri: location.uri,
    targetRange: location.range,
    targetSelectionRange: location.range,
  };
}

function getComponentContextAtPosition(line: string, charInLine: number): ComponentUsageContext | null {
  const tagStart = line.lastIndexOf('<', charInLine);
  if (tagStart === -1) {
    return null;
  }

  const after = line.slice(tagStart + 1);

  if (after.startsWith('/') || after.startsWith(':') || after.startsWith('%')) {
    return null;
  }

  if (after.startsWith('.')) {
    const nameMatch = after.slice(1).match(/^([a-z_][a-z0-9_]*)/);
    if (!nameMatch) {
      return null;
    }
    const nameStart = tagStart + 2;
    const nameEnd = nameStart + nameMatch[1].length;

    if (charInLine < nameStart || charInLine >= nameEnd) {
      return null;
    }

    return { componentName: nameMatch[1] };
  }

  const remoteMatch = after.match(/^([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.([a-z_][a-z0-9_]*)/);
  if (remoteMatch) {
    const moduleName = remoteMatch[1];
    const componentName = remoteMatch[2];
    const moduleStart = tagStart + 1;
    const moduleEnd = moduleStart + moduleName.length;
    const componentStart = moduleEnd + 1; // skip the dot
    const componentEnd = componentStart + componentName.length;

    if (charInLine >= componentStart && charInLine < componentEnd) {
      return {
        componentName,
        moduleContext: moduleName,
      };
    }

    return null;
  }

  return null;
}

interface SlotDetection {
  slotName: string;
  closing: boolean;
}

function detectSlotAtPosition(line: string, charInLine: number): SlotDetection | null {
  const openRegex = /<:([a-z_][a-z0-9_-]*)/g;
  let match: RegExpExecArray | null;
  while ((match = openRegex.exec(line)) !== null) {
    const tagStart = match.index;
    const nameStart = tagStart + 2;
    const nameEnd = nameStart + match[1].length;
    if (charInLine >= tagStart + 1 && charInLine <= nameEnd) {
      return { slotName: match[1], closing: false };
    }
  }

  const closeRegex = /<\/:([a-z_][a-z0-9_-]*)/g;
  while ((match = closeRegex.exec(line)) !== null) {
    const tagStart = match.index;
    const nameStart = tagStart + 3;
    const nameEnd = nameStart + match[1].length;
    if (charInLine >= tagStart + 1 && charInLine <= nameEnd) {
      return { slotName: match[1], closing: true };
    }
  }

  return null;
}

interface HeexBlock {
  start: number;
  text: string;
}

function updateHeexTreesForHeexDocument(filePath: string, content: string) {
  if (!isTreeSitterReady()) {
    return;
  }
  const activeKeys = new Set<string>([filePath]);
  getHeexTree(filePath, content);
  pruneHeexTreeCache(filePath, activeKeys);
}

function updateHeexTreesForElixirDocument(filePath: string, content: string) {
  if (!isTreeSitterReady()) {
    return;
  }
  const blocks = extractHeexBlocks(content);
  const activeKeys = new Set<string>();

  blocks.forEach(block => {
    const key = `${filePath}#${block.start}`;
    activeKeys.add(key);
    getHeexTree(key, block.text);
  });

  pruneHeexTreeCache(filePath, activeKeys);
}

function extractHeexBlocks(content: string): HeexBlock[] {
  const blocks: HeexBlock[] = [];
  const regex = /~H\s*("""|'''|"|')/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(content)) !== null) {
    const delimiter = match[1];
    const bodyStart = regex.lastIndex;
    let searchIndex = bodyStart;
    let closingIndex = -1;

    while (true) {
      closingIndex = content.indexOf(delimiter, searchIndex);
      if (closingIndex === -1) {
        break;
      }
      if (delimiter.length === 1 && content[closingIndex - 1] === '\\') {
        searchIndex = closingIndex + 1;
        continue;
      }
      break;
    }

    if (closingIndex === -1) {
      break;
    }

    const blockText = content.slice(bodyStart, closingIndex);
    blocks.push({ start: bodyStart, text: blockText });

    regex.lastIndex = closingIndex + delimiter.length;
  }

  return blocks;
}

function pruneHeexTreeCache(filePath: string, activeKeys: Set<string>) {
  const prefix = `${filePath}#`;
  getTreeCacheKeys().forEach(key => {
    if (key === filePath) {
      if (!activeKeys.has(filePath)) {
        clearTreeCache(key);
      }
    } else if (key.startsWith(prefix)) {
      if (!activeKeys.has(key)) {
        clearTreeCache(key);
      }
    }
  });
}

function clearHeexTreeCachesForFile(filePath: string) {
  pruneHeexTreeCache(filePath, new Set());
}

function buildSlotHoverDocumentation(
  component: PhoenixComponent,
  slotName: string,
  slot?: ComponentSlot
): string {
  let doc = `**Slot: \`<:${slotName}>\`**\n\n`;
  doc += `Provided by component \`<.${component.name}>\` (\`${component.moduleName}\`).\n\n`;

  if (slot) {
    doc += `- **Required:** ${slot.required ? 'Yes' : 'No'}\n`;

    if (slot.attributes && slot.attributes.length > 0) {
      doc += '- **Slot assigns:**\n';
      slot.attributes.forEach(attr => {
        const typeDisplay = getAttributeTypeDisplay(attr);
        doc += `  - \`@${attr.name}\`: \`${typeDisplay}\``;
        if (attr.required) {
          doc += ' (required)';
        }
        if (attr.default) {
          doc += ` (default: \`${attr.default}\`)`;
        }
        doc += '\n';
      });
    }

    if (slot.doc) {
      doc += `\n${slot.doc}\n`;
    }
  } else if (slotName === 'inner_block') {
    doc += 'Default slot for inner content passed between the opening and closing component tags.\n\n';
  } else {
    doc += 'This slot is accepted by the component, but additional metadata was not found in the registry.\n\n';
  }

  const fileName = path.basename(component.filePath);
  doc += `**Module:** \`${component.moduleName}\`\n`;
  doc += `**File:** \`${fileName}\` (line ${component.line})\n`;

  return doc;
}

function findComponentUsageAtName(usageStack: ComponentUsage[], offset: number): ComponentUsage | null {
  console.log('[findComponentUsageAtName] Searching for offset:', offset, 'in', usageStack.length, 'usages');
  for (let i = usageStack.length - 1; i >= 0; i--) {
    const usage = usageStack[i];
    const nameStart = usage.nameStart;
    const nameEnd = usage.nameEnd;
    console.log(`[findComponentUsageAtName]   Checking ${usage.componentName}: nameStart=${nameStart}, nameEnd=${nameEnd}`);
    console.log(`[findComponentUsageAtName]     Range check: ${offset} >= ${nameStart} && ${offset} <= ${nameEnd} = ${offset >= nameStart && offset <= nameEnd}`);
    if (offset >= nameStart && offset <= nameEnd) {
      console.log(`[findComponentUsageAtName]   ✅ FOUND: ${usage.componentName}`);
      return usage;
    }
    if (offset === nameStart - 1) {
      console.log(`[findComponentUsageAtName]   ✅ FOUND (edge case): ${usage.componentName}`);
      return usage;
    }
  }
  console.log('[findComponentUsageAtName]   ❌ NOT FOUND');
  return null;
}

function findFallbackComponentLocation(currentFilePath: string, componentName: string): Location | null {
  const workspaceRoot = componentsRegistry.getWorkspaceRoot();
  if (!workspaceRoot) {
    return null;
  }

  const parts = currentFilePath.split(path.sep);
  const libIndex = parts.indexOf('lib');
  if (libIndex === -1 || libIndex + 1 >= parts.length) {
    return null;
  }

  const appWeb = parts[libIndex + 1];
  const componentsRoot = path.join(workspaceRoot, 'lib', appWeb, 'components');
  const candidates = new Set<string>();

  const visitStack: string[] = [componentsRoot];
  while (visitStack.length > 0) {
    const dir = visitStack.pop()!;
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          visitStack.push(fullPath);
        } else if (entry.isFile() && entry.name.endsWith('.ex')) {
          candidates.add(path.normalize(fullPath));
        }
      }
    } catch {
      // ignore
    }
  }

  const singleFile = path.normalize(path.join(workspaceRoot, 'lib', appWeb, 'components.ex'));
  if (fs.existsSync(singleFile)) {
    candidates.add(singleFile);
  }

  for (const filePath of candidates) {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const regex = new RegExp(`^\s*defp?\s+${componentName}\b`, 'm');
      const match = regex.exec(content);
      if (!match) {
        continue;
      }

      const preceding = content.slice(0, match.index);
      const line = preceding.split('\n').length - 1;
      const lines = content.split('\n');
      const lineText = lines[line] ?? '';
      const character = Math.max(0, lineText.indexOf(componentName));

      debugLog('definition', `Fallback found component <.${componentName}> in ${filePath}:${line + 1}`);

      return {
        uri: URI.file(filePath).toString(),
        range: {
          start: { line, character },
          end: { line, character: character + componentName.length },
        },
      };
    } catch {
      // ignore errors reading file
    }
  }

  return null;
}

// Provide completions
connection.onCompletion(
  async (textDocumentPosition: TextDocumentPositionParams): Promise<CompletionList> => {
    const perfTimer = new PerfTimer('onCompletion');
    try {
      const document = documents.get(textDocumentPosition.textDocument.uri);
      if (!document) {
        return { items: [], isIncomplete: false };
      }

    const text = document.getText();
    const offset = document.offsetAt(textDocumentPosition.position);
    const uri = textDocumentPosition.textDocument.uri;
    const filePath = URI.parse(uri).fsPath;

    // Check if we're in an Elixir file
    const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');
    const isHeexFile = uri.endsWith('.heex');
    const insideSigil = isElixirFile ? isInsideHEExSigil(text, offset) : false;
    const insideTagContext = isInsideTagContext(text, offset);

    // Extract current line only (not last 100 chars which can span multiple lines)
    const lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    const linePrefix = text.substring(lineStart, offset);

    // Verbose completion logging disabled by default (too noisy)
    // Enable with: PHOENIX_PULSE_DEBUG=completion
    if (process.env.PHOENIX_PULSE_DEBUG?.includes('completion')) {
      console.log('========================================');
      console.log('[COMPLETION] Request received');
      console.log('[COMPLETION] filePath:', filePath);
      console.log('[COMPLETION] position:', textDocumentPosition.position);
      console.log('[COMPLETION] offset:', offset);
      console.log('[COMPLETION] linePrefix:', JSON.stringify(linePrefix));
      console.log('[COMPLETION] isElixirFile:', isElixirFile, 'isHeexFile:', isHeexFile, 'insideSigil:', insideSigil);
      console.log('========================================');
    }

    const completions: CompletionItem[] = [];
    let specialAttributesAdded = false;

    if (isInsideJsPushEvent(linePrefix)) {
      const jsEventCompletions = getJsPushEventCompletions(filePath, eventsRegistry);
      if (jsEventCompletions.length > 0) {
        return { items: jsEventCompletions, isIncomplete: false };
      }
    }

    // Check for @ and assigns. contexts
    // Rules:
    // - .heex files: Both @ and assigns. work everywhere
    // - .ex files inside ~H: Both @ and assigns. work
    // - .ex files outside ~H: ONLY assigns. works (@ means module attribute!)
    const atContext = isAtSignContext(linePrefix);
    const assignsContext = isAssignsContext(linePrefix);
    const forLoopVarContext = isForLoopVariableContext(linePrefix, text, offset);

    if (process.env.PHOENIX_PULSE_DEBUG?.includes('completion')) {
      console.log('[completion] atContext:', atContext, 'assignsContext:', assignsContext, 'forLoopVarContext:', forLoopVarContext);
    }

    // Check for Phoenix/LiveView-specific snippets
    // For @ event shortcuts: Add to completions (merge with assigns)
    // For other snippets (.live, :for, form.phx): Return early (specific, don't mix)
    const phoenixSnippets = getPhoenixSnippetCompletions(linePrefix, document, textDocumentPosition.position);
    if (phoenixSnippets.length > 0) {
      // Check if these are @ event shortcuts (should merge with assigns)
      const hasEventShortcuts = phoenixSnippets.every(item => item.label.startsWith('@'));

      if (hasEventShortcuts) {
        // Add @ events to completions array, let assigns also show
        completions.push(...phoenixSnippets);
      } else {
        // Non-@ snippets (.live, :for, etc.) return early
        return { items: phoenixSnippets, isIncomplete: false };
      }
    }

    let shouldShowAssignCompletions = false;
    if (isHeexFile) {
      // .heex files: @, assigns., and :for loop variables work
      shouldShowAssignCompletions = atContext || assignsContext || forLoopVarContext;
    } else if (isElixirFile) {
      if (insideSigil) {
        // Inside ~H sigil: @, assigns., and :for loop variables work
        shouldShowAssignCompletions = atContext || assignsContext || forLoopVarContext;
      } else {
        // Outside sigil: ONLY assigns. works (@ is module attribute)
        // But :for loop variables should also work
        shouldShowAssignCompletions = assignsContext || forLoopVarContext;
      }
    }

    if (shouldShowAssignCompletions) {
      if (process.env.PHOENIX_PULSE_DEBUG?.includes('completion')) {
        console.log('[completion] Triggering assign completions');
      }
      const assignCompletions = getAssignCompletions(
        componentsRegistry,
        schemaRegistry,
        controllersRegistry,
        filePath,
        offset,
        text,
        linePrefix
      );
      return { items: [...completions, ...assignCompletions], isIncomplete: false }; // Merge event shortcuts with assigns
    }

    if (isElixirFile) {
      const handleInfoCompletions = getHandleInfoEventCompletions(
        linePrefix,
        textDocumentPosition.position,
        filePath,
        eventsRegistry
      );
      if (handleInfoCompletions && handleInfoCompletions.length > 0) {
        return { items: handleInfoCompletions, isIncomplete: false };
      }
    }

    const routeHelperCompletions = getRouteHelperCompletions(
      document,
      textDocumentPosition.position,
      linePrefix,
      routerRegistry
    );
    if (routeHelperCompletions && routeHelperCompletions.length > 0) {
      return { items: routeHelperCompletions, isIncomplete: false };
    }

    // Check for controller template completions (render(conn, :template))
    if (isElixirFile && filePath.endsWith('_controller.ex')) {
      const templateCompletions = getTemplateCompletions(
        filePath,
        linePrefix,
        templatesRegistry,
        text
      );
      if (templateCompletions && templateCompletions.length > 0) {
        return { items: templateCompletions, isIncomplete: false };
      }
    }

    // Check for asset completions (~p"/images/...") FIRST
    // Assets should take priority over route completions for static paths
    const assetCompletions = getAssetCompletions(
      document,
      textDocumentPosition.position,
      linePrefix,
      assetRegistry
    );
    if (assetCompletions && assetCompletions.length > 0) {
      console.log(`[server] Returning ${assetCompletions.length} asset completions`);
      return { items: assetCompletions, isIncomplete: false };
    }

    // Check for verified route completions (~p"/path")
    // These can appear anywhere in Elixir code, not just in templates
    const routeCompletions = getVerifiedRouteCompletions(
      document,
      textDocumentPosition.position,
      linePrefix,
      routerRegistry
    );
    if (routeCompletions && routeCompletions.length > 0) {
      return { items: routeCompletions, isIncomplete: false };
    }

    // For Elixir files, only provide other completions inside ~H sigils
    // This applies to: Phoenix attributes, HTML attributes, components, and Emmet
    if (isElixirFile && !insideSigil) {
      return { items: [], isIncomplete: false }; // Early return prevents all other completions outside sigils
    }

    // IMPORTANT: Check if cursor is inside a phx-* attribute value EARLY (before component attrs pollute completions array)
    // This regex finds: phx-click="text_before_cursor█
    const insidePhxAttribute = /phx-(?:click|submit|change|blur|focus|key|keydown|keyup|window-keydown|window-keyup|capture-click|click-away)=["']([^"']*)$/.test(linePrefix);

    if (insidePhxAttribute) {
      // Check if already typing JS. - if so, provide JS completions
      if (/phx-[a-z-]+\s*=\s*["']\s*JS\./.test(linePrefix)) {
        completions.push(...getJSCommandCompletions());
        return { items: completions, isIncomplete: false };
      }

      // Provide event name suggestions from handle_event definitions
      const { primary } = eventsRegistry.getEventsForTemplate(filePath);

      // Add primary events (from same module) with higher priority
      primary.forEach((event, index) => {
        completions.push(createEventCompletionItem(event, '0', index));
      });

      // Early return - only show events for phx-* attribute string values
      return { items: completions, isIncomplete: false };
    }

    // Check if we're in a local component context (e.g., <.█)
    if (isLocalComponentContext(linePrefix)) {
      connection.console.log(`[Server] Component context detected! linePrefix: "${linePrefix.slice(-20)}"`);
      const componentCompletions = getLocalComponentCompletions(componentsRegistry, filePath);
      connection.console.log(`[Server] Returning ${componentCompletions.length} component completions`);
      completions.push(...componentCompletions);
      return { items: completions, isIncomplete: false }; // Early return - only show component names
    }

    // Check if we're inside a component tag and need attribute completions
    const componentName = getComponentNameFromContext(linePrefix);
    if (componentName && insideTagContext) {
      const moduleContext = getModuleNameFromContext(linePrefix);
      const component = componentsRegistry.resolveComponent(filePath, componentName, {
        moduleContext: moduleContext || undefined,
        fileContent: isElixirFile ? text : undefined,
      });
      if (component) {
        const attrCompletions = getComponentAttributeCompletions(component);
        completions.push(...attrCompletions);
        // Also add special template attributes to components
        completions.push(...getSpecialAttributeCompletions(document, textDocumentPosition.position, linePrefix));
        specialAttributesAdded = true;
        // Continue to also add HTML/Phoenix attributes (no early return)
      }
    }

    const formFieldCompletions = getFormFieldCompletions(
      document,
      text,
      offset,
      linePrefix,
      schemaRegistry,
      componentsRegistry,
      filePath
    );
    if (formFieldCompletions && formFieldCompletions.length > 0) {
      return { items: formFieldCompletions, isIncomplete: false };
    }

    // Check if we're in a slot context (<:slot_name)
    const slotContext = /<:([a-z_][a-z0-9_]*)?$/.exec(linePrefix);
    if (slotContext && insideTagContext) {
      const usageContext = findEnclosingComponentUsage(text, offset);
      if (usageContext) {
        const component = componentsRegistry.resolveComponent(filePath, usageContext.componentName, {
          moduleContext: usageContext.moduleContext,
          fileContent: isElixirFile ? text : undefined,
        });

        if (component && component.slots.length > 0) {
          const slotCompletions = getComponentSlotCompletions(component);
          completions.push(...slotCompletions);
          return { items: completions, isIncomplete: false };
        }
      }
    }

    // Check if we're in a pipe chain context (e.g., JS.show(...) |> █)
    if (isPipeChainContext(linePrefix)) {
      // Provide chainable JS command completions
      completions.push(...getChainableJSCompletions());
      return { items: completions, isIncomplete: false }; // Early return - only show chainable commands
    }

    // Check if we're in a JS command context (e.g., phx-click={JS.█ or phx-click="JS.█)
    if (isJSCommandContext(linePrefix)) {
      // Provide JS command completions
      completions.push(...getJSCommandCompletions());
      return { items: completions, isIncomplete: false }; // Early return - only show JS commands
    }

    // Note: phx-* attribute value check has been moved earlier (before component attrs)
    // to prevent component attributes from polluting the completions array

    // Check if we're in an HTML tag context (for attribute name suggestions)
    const inTag = /<[a-zA-Z][a-zA-Z0-9]*\s+[^>]*$/.test(linePrefix);
    const inAttribute = /\s[a-zA-Z-_:]*$/.test(linePrefix);

    if (insideTagContext && (inTag || inAttribute)) {
      // Special template attributes (:for, :if, :let, :key)
      if (!specialAttributesAdded) {
        completions.push(...getSpecialAttributeCompletions(document, textDocumentPosition.position, linePrefix));
      }

      // Phoenix attribute completions (context-aware + event-aware)
      const elementContext = getElementContext(linePrefix);

      // Check if current LiveView has handle_event callbacks
      const { primary } = eventsRegistry.getEventsForTemplate(filePath);
      const hasEvents = primary.length > 0;

      completions.push(...getPhoenixCompletions(elementContext, hasEvents));

      // Context-aware phx-value-* completions (based on :for loop variable fields)
      completions.push(...getContextAwarePhxValueCompletions(
        text,
        offset,
        linePrefix,
        filePath,
        componentsRegistry,
        controllersRegistry,
        schemaRegistry
      ));

      // Check for HTML attribute VALUE completions first (inside quotes)
      // Example: <input type="█"> should show value suggestions
      const htmlValueCompletions = getHtmlAttributeValueCompletions(linePrefix);
      if (htmlValueCompletions.length > 0) {
        return { items: htmlValueCompletions, isIncomplete: false }; // Early return
      }

      // HTML attribute NAME completions (context-aware)
      completions.push(...getSmartHtmlCompletions(linePrefix));
    }

    // Emmet completions (context-aware: skips inside {} and ~H sigils)
    const emmetCompletions = await getEmmetCompletions(
      document,
      textDocumentPosition.position,
      linePrefix,
      text,
      offset
    );

    // If we have emmet completions for emmet-specific syntax (containing #, ., >, +, *),
    // return ONLY emmet to prevent other language servers (Elixir) from competing
    const hasEmmetSyntax = /[.#>+*]/.test(linePrefix);
    if (emmetCompletions.length > 0 && hasEmmetSyntax) {
      console.log('[EMMET] Early return - emmet-specific syntax detected, preventing other completions');
      // Set isIncomplete: true to force VS Code to re-query on every keystroke
      // This makes completions more responsive and helps override other language servers
      return { items: emmetCompletions, isIncomplete: true };
    }

    completions.push(...emmetCompletions);

    return { items: completions, isIncomplete: false };
    } finally {
      perfTimer.stop();
    }
  }
);

connection.onCompletionResolve((item: CompletionItem): CompletionItem => {
  return item;
});

// Hover provider for documentation
connection.onHover((textDocumentPosition: TextDocumentPositionParams): Hover | null => {
  const perfTimer = new PerfTimer('onHover');
  try {
    const document = documents.get(textDocumentPosition.textDocument.uri);
    if (!document) {
      return null;
    }

  const text = document.getText();
  const offset = document.offsetAt(textDocumentPosition.position);
  const uri = textDocumentPosition.textDocument.uri;
  const filePath = URI.parse(uri).fsPath;

  // Check if we're in an Elixir file
  const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');

  // Get word at cursor position
  const lineStart = text.lastIndexOf('\n', offset - 1) + 1;
  const lineEnd = text.indexOf('\n', offset);
  const line = text.substring(lineStart, lineEnd === -1 ? text.length : lineEnd);
  const charInLine = offset - lineStart;

  // Find word boundaries
  let wordStart = charInLine;
  let wordEnd = charInLine;

  while (wordStart > 0 && /[a-zA-Z0-9_-]/.test(line[wordStart - 1])) {
    wordStart--;
  }
  while (wordEnd < line.length && /[a-zA-Z0-9_-]/.test(line[wordEnd])) {
    wordEnd++;
  }

  const word = line.substring(wordStart, wordEnd);

  // Get context around cursor (needed for multiple checks)
  const contextBefore = text.substring(Math.max(0, offset - 50), offset);
  const contextAfter = text.substring(offset, Math.min(text.length, offset + 10));
  const templateFileContent = isElixirFile ? text : undefined;

  // DEBUG: Log every hover request
  if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
    console.log('========================================');
    console.log('[HOVER] Request received');
    console.log('[HOVER] filePath:', filePath);
    console.log('[HOVER] position:', textDocumentPosition.position);
    console.log('[HOVER] offset:', offset);
    console.log('[HOVER] word:', JSON.stringify(word));
    console.log('[HOVER] contextBefore:', JSON.stringify(contextBefore));
    console.log('[HOVER] contextAfter:', JSON.stringify(contextAfter));
    console.log('[HOVER] isElixirFile:', isElixirFile);
    console.log('========================================');
  }

  const usageStack = getComponentUsageStack(text, offset, filePath);

  const slotContext = detectSlotAtPosition(line, charInLine);
  if (slotContext && usageStack.length > 0) {
    const parentUsage = usageStack[usageStack.length - 1];
    const parentComponent = componentsRegistry.resolveComponent(filePath, parentUsage.componentName, {
      moduleContext: parentUsage.moduleContext,
      fileContent: templateFileContent,
    });

    if (parentComponent) {
      const slotMeta = parentComponent.slots.find(slot => slot.name === slotContext.slotName);
      const slotDoc = buildSlotHoverDocumentation(parentComponent, slotContext.slotName, slotMeta);
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: slotDoc,
        },
      };
    }
  }

  // Check if hovering over @attribute (e.g., @variant, @size)
  // This works both inside and outside ~H sigils
  if (isElixirFile && contextBefore.match(/@([a-z_][a-z0-9_]*)$/)) {
    const attrName = word;
    const attributes = componentsRegistry.getCurrentComponentAttributes(filePath, offset, text);

    if (attributes) {
      const attribute = attributes.find(attr => attr.name === attrName);
      if (attribute) {
        let doc = `**Attribute: \`@${attribute.name}\`**\n\n`;
        doc += `- **Type:** \`:${attribute.type}\`\n`;
        doc += `- **Required:** ${attribute.required ? 'Yes' : 'No'}\n`;

        if (attribute.default) {
          doc += `- **Default:** \`${attribute.default}\`\n`;
        }

        if (attribute.values && attribute.values.length > 0) {
          doc += `- **Values:** ${attribute.values.map(v => `\`:${v}\``).join(', ')}\n`;
        }

        if (attribute.doc) {
          doc += `\n${attribute.doc}\n`;
        }

        return {
          contents: {
            kind: MarkupKind.Markdown,
            value: doc,
          },
        };
      }
    }
  }

  // Check if hovering over assigns.attribute (e.g., assigns.variant)
  if (isElixirFile && contextBefore.match(/assigns\.([a-z_][a-z0-9_]*)$/)) {
    const attrName = word;
    const attributes = componentsRegistry.getCurrentComponentAttributes(filePath, offset, text);

    if (attributes) {
      const attribute = attributes.find(attr => attr.name === attrName);
      if (attribute) {
        let doc = `**Attribute: \`assigns.${attribute.name}\`**\n\n`;
        doc += `- **Type:** \`:${attribute.type}\`\n`;
        doc += `- **Required:** ${attribute.required ? 'Yes' : 'No'}\n`;

        if (attribute.default) {
          doc += `- **Default:** \`${attribute.default}\`\n`;
        }

        if (attribute.values && attribute.values.length > 0) {
          doc += `- **Values:** ${attribute.values.map(v => `\`:${v}\``).join(', ')}\n`;
        }

        if (attribute.doc) {
          doc += `\n${attribute.doc}\n`;
        }

        return {
          contents: {
            kind: MarkupKind.Markdown,
            value: doc,
          },
        };
      }
    }
  }

  // Check if hovering over schema association (e.g., @user.organization, @event.product)
  // This handles both @assign.field and assigns.assign.field patterns
  if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
    console.log('[hover] contextBefore:', JSON.stringify(contextBefore));
    console.log('[hover] word:', word);
    console.log('[hover] contextAfter:', JSON.stringify(contextAfter));
  }

  // FIX: Don't rely on regex to capture full field path - contextBefore ends at cursor!
  // Instead, detect the pattern and combine with the word at cursor

  // Pattern 1: @assign.field (hovering over "field")
  // Example: "@event.product" - contextBefore might be "@event.pro", word is "product"
  const atAssignPattern = /@([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_.]*)$/;
  const atMatch = contextBefore.match(atAssignPattern);

  if (atMatch && word && (isElixirFile || isInsideHEExSigil(text, offset))) {
    const baseAssign = atMatch[1];
    const partialPath = atMatch[2] || '';

    // Combine partial path from contextBefore with word at cursor
    // If contextBefore ends with a partial match of word, use just the word
    // Otherwise, append word to partial path
    let fullPath: string;
    if (word.startsWith(partialPath)) {
      // contextBefore has "@event.pro", word is "product" -> use "product"
      fullPath = word;
    } else {
      // contextBefore has "@event.product.n", word is "name" -> use "product.name"
      fullPath = partialPath ? `${partialPath}.${word}` : word;
    }

    if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
      console.log('[hover] @ pattern detected:', { baseAssign, partialPath, word, fullPath });
    }

    // Try to get schema association info
    const associationInfo = schemaRegistry.getAssociationInfoFromPath(
      componentsRegistry,
      controllersRegistry,
      filePath,
      baseAssign,
      fullPath.split('.').filter(p => p.length > 0),
      offset,
      text
    );

    if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
      console.log('[hover] associationInfo:', associationInfo);
    }

    if (associationInfo) {
      let doc = `**${associationInfo.associationType}** → \`${associationInfo.targetModule}\`\n\n`;

      if (associationInfo.fields && associationInfo.fields.length > 0) {
        doc += `**Available fields:**\n`;
        const fieldList = associationInfo.fields.slice(0, 10).join(', ');
        doc += fieldList;
        if (associationInfo.fields.length > 10) {
          doc += `, ...and ${associationInfo.fields.length - 10} more`;
        }
      }

      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // Pattern 2: assigns.assign.field (hovering over "field")
  const assignsAssignPattern = /assigns\.([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_.]*)$/;
  const assignsMatch = contextBefore.match(assignsAssignPattern);

  if (assignsMatch && word && (isElixirFile || isInsideHEExSigil(text, offset))) {
    const baseAssign = assignsMatch[1];
    const partialPath = assignsMatch[2] || '';

    let fullPath: string;
    if (word.startsWith(partialPath)) {
      fullPath = word;
    } else {
      fullPath = partialPath ? `${partialPath}.${word}` : word;
    }

    if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
      console.log('[hover] assigns. pattern detected:', { baseAssign, partialPath, word, fullPath });
    }

    const associationInfo = schemaRegistry.getAssociationInfoFromPath(
      componentsRegistry,
      controllersRegistry,
      filePath,
      baseAssign,
      fullPath.split('.').filter(p => p.length > 0),
      offset,
      text
    );

    if (process.env.PHOENIX_PULSE_DEBUG?.includes('hover')) {
      console.log('[hover] associationInfo:', associationInfo);
    }

    if (associationInfo) {
      let doc = `**${associationInfo.associationType}** → \`${associationInfo.targetModule}\`\n\n`;

      if (associationInfo.fields && associationInfo.fields.length > 0) {
        doc += `**Available fields:**\n`;
        const fieldList = associationInfo.fields.slice(0, 10).join(', ');
        doc += fieldList;
        if (associationInfo.fields.length > 10) {
          doc += `, ...and ${associationInfo.fields.length - 10} more`;
        }
      }

      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // For Elixir files, only provide other hover inside ~H sigils
  if (isElixirFile && !isInsideHEExSigil(text, offset)) {
    return null;
  }

  // Only show component hover when cursor is directly ON component name
  // Don't use usageStack fallback - prevents showing parent component docs on HTML elements
  const componentUsage = getComponentContextAtPosition(line, charInLine) || findComponentUsageAtName(usageStack, offset);
  if (componentUsage) {
    const component = componentsRegistry.resolveComponent(filePath, componentUsage.componentName, {
      moduleContext: componentUsage.moduleContext,
      fileContent: templateFileContent,
    });
    if (component) {
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: buildComponentHoverDocumentation(component),
        },
      };
    }
  }

  // Check if hovering over a component attribute
  // Pattern: <.component_name attribute_name=
  const componentAttrPattern = getLastRegexMatch(contextBefore, /<\.([a-z_][a-z0-9_]*)\s+[^>]*\b([a-z_][a-z0-9_]*)\s*=/g);
  if (componentAttrPattern && word === componentAttrPattern[2]) {
    const componentName = componentAttrPattern[1];
    const attributeName = word;
    const component = componentsRegistry.resolveComponent(filePath, componentName, {
      fileContent: templateFileContent,
    });
    if (component) {
      const attrDoc = buildAttributeHoverDocumentation(component, attributeName);
      if (attrDoc) {
        return {
          contents: {
            kind: MarkupKind.Markdown,
            value: attrDoc,
          },
        };
      }
    }
  } else {
    const remoteComponentAttrPattern = getLastRegexMatch(contextBefore, /<([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.([a-z_][a-z0-9_]*)\s+[^>]*\b([a-z_][a-z0-9_]*)\s*=/g);
    if (remoteComponentAttrPattern && word === remoteComponentAttrPattern[3]) {
      const moduleContext = remoteComponentAttrPattern[1];
      const componentName = remoteComponentAttrPattern[2];
      const attributeName = remoteComponentAttrPattern[3];
      const component = componentsRegistry.resolveComponent(filePath, componentName, {
        moduleContext,
        fileContent: templateFileContent,
      });
      if (component) {
        const attrDoc = buildAttributeHoverDocumentation(component, attributeName);
        if (attrDoc) {
          return {
            contents: {
              kind: MarkupKind.Markdown,
              value: attrDoc,
            },
          };
        }
      }
    }
  }

  // Check if hovering over a phx- attribute
  // Now uses rich documentation from completions/phoenix.ts
  if (word.startsWith('phx-') || word === 'phx') {
    const doc = getPhoenixAttributeDocumentation(word);
    if (doc) {
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // Check if hovering over an event name in a phx attribute value
  // Check if we're inside a phx-* attribute value
  const insidePhxValue = /phx-(?:click|submit|change|blur|focus|key|keydown|keyup|window-keydown|window-keyup)=["']([^"']*)$/.test(contextBefore);

  if (insidePhxValue && word && !word.startsWith('phx-') && !word.startsWith('JS.')) {
    // Try to find this event in the registry
    const filePath = URI.parse(uri).fsPath;
    const { primary, secondary } = eventsRegistry.getEventsForTemplate(filePath);
    const allEvents = [...primary, ...secondary];

    const event = allEvents.find(e => e.name === word);
    if (event) {
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: buildEventMarkdown(event),
        },
      };
    }
  }

  // Check if hovering over JS command
  if (word.startsWith('JS.') || (contextBefore.includes('JS.') && word.match(/^[a-z_]+$/))) {
    const jsCommand = word.startsWith('JS.') ? word : `JS.${word}`;
    const jsCommandDocs: { [key: string]: string } = {
      'JS.show': '**Show element(s) with optional transitions**\n\n```elixir\nJS.show("#modal", transition: "fade-in", time: 300)\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#show/2)',
      'JS.hide': '**Hide element(s) with optional transitions**\n\n```elixir\nJS.hide("#modal", transition: "fade-out", time: 300)\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#hide/2)',
      'JS.toggle': '**Toggle element visibility**\n\n```elixir\nJS.toggle("#dropdown", in: "fade-in", out: "fade-out")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#toggle/2)',
      'JS.add_class': '**Add CSS class(es) to element(s)**\n\n```elixir\nJS.add_class("#button", "active")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#add_class/3)',
      'JS.remove_class': '**Remove CSS class(es) from element(s)**\n\n```elixir\nJS.remove_class("#button", "active")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#remove_class/3)',
      'JS.toggle_class': '**Toggle CSS class(es) on element(s)**\n\n```elixir\nJS.toggle_class("#menu", "open")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#toggle_class/3)',
      'JS.push': '**Push event to server**\n\n```elixir\nJS.push("save", value: %{id: 1})\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#push/2)',
      'JS.navigate': '**Navigate to URL (full page load)**\n\n```elixir\nJS.navigate("/users")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#navigate/2)',
      'JS.patch': '**Patch LiveView (no page reload)**\n\n```elixir\nJS.patch("/users?page=2")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#patch/2)',
      'JS.focus': '**Focus element**\n\n```elixir\nJS.focus("#search-input")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#focus/2)',
      'JS.dispatch': '**Dispatch custom DOM event**\n\n```elixir\nJS.dispatch("click", to: "#button")\n```\n\n[HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#dispatch/3)',
    };

    const doc = jsCommandDocs[jsCommand];
    if (doc) {
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // Check if hovering over route helper (Routes.user_path, etc.)
  const routeHelperMatch = contextBefore.match(/Routes\.([a-z_]+)_(path|url)\b/);
  if (routeHelperMatch) {
    const helperBase = routeHelperMatch[1];
    const variant = routeHelperMatch[2];
    const routes = routerRegistry.findRoutesByHelper(helperBase);

    if (routes.length > 0) {
      const route = routes[0];
      let doc = `**Routes.${helperBase}_${variant}**\n\n`;

      // Show verb and path
      const allVerbs = Array.from(new Set(routes.map(r => r.verb))).join(', ');
      const allPaths = Array.from(new Set(routes.map(r => r.path)));

      doc += `- **Verbs:** ${allVerbs}\n`;
      doc += `- **Path${allPaths.length > 1 ? 's' : ''}:**\n`;
      allPaths.forEach(p => {
        doc += `  - \`${p}\`\n`;
      });

      // Show parameters
      if (route.params.length > 0) {
        doc += `- **Parameters:** ${route.params.map(p => `\`${p}\``).join(', ')}\n`;
      }

      // Show controller/action or LiveView module
      if (route.liveModule) {
        doc += `- **LiveView:** ${route.liveModule}\n`;
      } else if (route.controller) {
        doc += `- **Controller:** ${route.controller}\n`;
        if (route.action) {
          doc += `- **Action:** :${route.action}\n`;
        }
      }

      // Show pipeline
      if (route.pipeline) {
        doc += `- **Pipeline:** :${route.pipeline}\n`;
      }

      // Show definition location
      doc += `\n*Defined in ${path.basename(route.filePath)}:${route.line}*`;

      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // Check if hovering over ~p sigil path
  const verifiedRouteMatch = contextBefore.match(/~p"([^"]*)$/);
  if (verifiedRouteMatch) {
    const routePath = verifiedRouteMatch[1];
    const route = routerRegistry.findRouteByPath(routePath);

    if (route) {
      let doc = `**Verified Route: \`${route.path}\`**\n\n`;
      doc += `- **Verb:** ${route.verb}\n`;

      // Show controller/action or LiveView module
      if (route.liveModule) {
        doc += `- **LiveView:** ${route.liveModule}\n`;
      } else if (route.controller) {
        doc += `- **Controller:** ${route.controller}\n`;
        if (route.action) {
          doc += `- **Action:** :${route.action}\n`;
        }
      }

      // Show parameters
      if (route.params.length > 0) {
        doc += `- **Parameters:** ${route.params.map(p => `\`${p}\``).join(', ')}\n`;
      }

      // Show pipeline
      if (route.pipeline) {
        doc += `- **Pipeline:** :${route.pipeline}\n`;
      }

      // Show definition location
      doc += `\n*Defined in ${path.basename(route.filePath)}:${route.line}*`;

      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: doc,
        },
      };
    }
  }

  // Check if hovering over template in controller render call
  if (isElixirFile && filePath.endsWith('_controller.ex')) {
    // Use same atom detection as go-to-definition
    let atomStart = offset;
    let atomEnd = offset;

    // Find start of atom (look backwards for : or start of word)
    while (atomStart > 0 && /[a-z0-9_:]/.test(text[atomStart - 1])) {
      atomStart--;
    }

    // Find end of atom (look forwards for end of word)
    while (atomEnd < text.length && /[a-z0-9_]/.test(text[atomEnd])) {
      atomEnd++;
    }

    const atomText = text.substring(atomStart, atomEnd);
    const atomMatch = atomText.match(/^:([a-z_][a-z0-9_]*)$/);

    if (atomMatch) {
      const templateName = atomMatch[1];

      // Check if we're in a render call context
      const contextBefore = text.substring(Math.max(0, atomStart - 200), atomStart);
      const isInRenderCall = /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*$/.test(contextBefore);

      if (isInRenderCall) {
        // Extract controller module from file content (to get full namespace)
        let controllerModule: string | null = null;
        const moduleMatch = text.match(/defmodule\s+([\w.]+Controller)\s+do/);
        if (moduleMatch) {
          controllerModule = moduleMatch[1];
        } else {
          // Fallback to file path extraction
          const fileMatch = filePath.match(/([a-z_]+)_controller\.ex$/);
          if (fileMatch) {
            const baseName = fileMatch[1];
            const pascalCase = baseName
              .split('_')
              .map(part => part.charAt(0).toUpperCase() + part.slice(1))
              .join('');
            controllerModule = `${pascalCase}Controller`;
          }
        }

        if (controllerModule) {
          const htmlModule = controllerModule.replace(/Controller$/, 'HTML');

          // Find template
          const template = templatesRegistry.getTemplateByModule(htmlModule, templateName, 'html');

      if (template) {
        const isEmbedded = template.filePath.endsWith('.ex');
        const templateType = isEmbedded ? 'Embedded template function' : 'Template file';
        const fileName = path.basename(template.filePath);

        let doc = `**Template:** \`${template.name}\`\n\n`;
        doc += `- **Type:** ${templateType}\n`;
        doc += `- **Module:** ${template.moduleName}\n`;
        doc += `- **File:** ${fileName}\n`;
        doc += `\n*Location: ${template.filePath}*`;

        return {
          contents: {
            kind: MarkupKind.Markdown,
            value: doc,
          },
        };
      }
        }
      }
    }
  }

  return null;
  } finally {
    perfTimer.stop();
  }
});

// Signature Help provider for component attributes
connection.onSignatureHelp((params: TextDocumentPositionParams): SignatureHelp | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return null;
  }

  const text = document.getText();
  const offset = document.offsetAt(params.position);
  const uri = params.textDocument.uri;
  const filePath = URI.parse(uri).fsPath;

  // Check if we're in an Elixir file
  const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');

  // For Elixir files, only provide signature help inside ~H sigils
  if (isElixirFile && !isInsideHEExSigil(text, offset)) {
    return null;
  }

  // Get line up to cursor
  const lineStart = text.lastIndexOf('\n', offset - 1) + 1;
  const linePrefix = text.substring(lineStart, offset);

  // Detect if we're inside a component tag
  // Pattern: <.component_name ... or <Module.component_name ...
  const componentMatch = linePrefix.match(/<(?:([A-Z][a-zA-Z0-9]*(?:\.[A-Z][a-zA-Z0-9]*)*)\.)?([a-z_][a-z0-9_]*)\s+[^>]*$/);

  if (!componentMatch) {
    return null;
  }

  const moduleContext = componentMatch[1];
  const componentName = componentMatch[2];

  // Resolve the component
  const component = componentsRegistry.resolveComponent(filePath, componentName, {
    moduleContext: moduleContext || undefined,
    fileContent: isElixirFile ? text : undefined,
  });

  if (!component) {
    return null;
  }

  // Build signature information
  const requiredAttrs = component.attributes.filter(attr => attr.required);
  const optionalAttrs = component.attributes.filter(attr => !attr.required);

  let label = `<.${component.name}`;
  const parameters: ParameterInformation[] = [];

  // Add required attributes
  if (requiredAttrs.length > 0) {
    requiredAttrs.forEach(attr => {
      const paramStart = label.length + 1;
      label += ` ${attr.name}`;
      parameters.push({
        label: [paramStart, label.length],
        documentation: {
          kind: MarkupKind.Markdown,
          value: `**Required** - Type: \`:${attr.type}\`${attr.doc ? `\n\n${attr.doc}` : ''}`,
        },
      });
    });
  }

  // Add optional attributes indicator
  if (optionalAttrs.length > 0) {
    const paramStart = label.length + 1;
    label += ` [...]`;
    parameters.push({
      label: [paramStart, label.length],
      documentation: {
        kind: MarkupKind.Markdown,
        value: `**Optional attributes:** ${optionalAttrs.map(a => a.name).join(', ')}`,
      },
    });
  }

  label += `>`;

  let documentation = `Component from **${component.moduleName}**\n\n`;

  if (requiredAttrs.length > 0) {
    documentation += `**Required:** ${requiredAttrs.map(a => `\`${a.name}\``).join(', ')}\n\n`;
  }

  if (optionalAttrs.length > 0) {
    documentation += `**Optional:** ${optionalAttrs.map(a => {
      let desc = `\`${a.name}\``;
      if (a.default) {
        desc += ` (default: \`${a.default}\`)`;
      }
      return desc;
    }).join(', ')}\n\n`;
  }

  if (component.doc) {
    documentation += component.doc;
  }

  const signature: SignatureInformation = {
    label,
    documentation: {
      kind: MarkupKind.Markdown,
      value: documentation,
    },
    parameters,
  };

  return {
    signatures: [signature],
    activeSignature: 0,
    activeParameter: null,
  };
});

// Code Action provider for quick fixes
connection.onCodeAction((params: CodeActionParams): CodeAction[] | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return null;
  }

  const codeActions: CodeAction[] = [];
  const text = document.getText();

  // Filter diagnostics that are actionable
  for (const diagnostic of params.context.diagnostics) {
    if (diagnostic.source !== 'phoenix-lsp') {
      continue;
    }

    // Fix: Add missing required attribute
    if (diagnostic.code === 'component-missing-attribute') {
      const match = diagnostic.message.match(/missing required attribute "([^"]+)"/);
      if (match) {
        const attrName = match[1];
        const componentMatch = diagnostic.message.match(/Component "([^"]+)"/);
        const componentName = componentMatch ? componentMatch[1] : 'component';

        // Find the component tag to insert the attribute
        const rangeText = document.getText(diagnostic.range);
        const offset = document.offsetAt(diagnostic.range.start);

        // Find the end of the opening tag
        let insertPos = offset;
        let depth = 0;
        for (let i = offset; i < text.length; i++) {
          const ch = text[i];
          if (ch === '<') depth++;
          if (ch === '>') {
            depth--;
            if (depth === 0) {
              insertPos = i;
              break;
            }
          }
        }

        // Check if it's a self-closing tag
        const beforeClose = text.substring(insertPos - 2, insertPos);
        const isSelfClosing = beforeClose === ' /';
        const insertPosition = isSelfClosing
          ? document.positionAt(insertPos - 2)
          : document.positionAt(insertPos);

        const action: CodeAction = {
          title: `Add required attribute "${attrName}"`,
          kind: CodeActionKind.QuickFix,
          diagnostics: [diagnostic],
          edit: {
            changes: {
              [params.textDocument.uri]: [
                TextEdit.insert(insertPosition, ` ${attrName}={$1}`),
              ],
            },
          },
        };
        codeActions.push(action);
      }
    }

    // Fix: Add component import
    if (diagnostic.code === 'component-not-imported') {
      const match = diagnostic.message.match(/import (.+)$/);
      if (match) {
        const moduleName = match[1];
        const uri = params.textDocument.uri;
        const filePath = URI.parse(uri).fsPath;

        // Find the HTML module file
        const htmlModuleFile = componentsRegistry.getHtmlModuleForTemplate(filePath);
        if (htmlModuleFile) {
          // Find the position to insert the import (after other imports)
          const htmlModuleDoc = documents.get(`file://${htmlModuleFile}`);
          if (htmlModuleDoc) {
            const htmlModuleText = htmlModuleDoc.getText();
            const lines = htmlModuleText.split('\n');

            // Find last import line
            let lastImportLine = -1;
            for (let i = 0; i < lines.length; i++) {
              if (lines[i].trim().startsWith('import ')) {
                lastImportLine = i;
              }
            }

            // Insert after last import or at the beginning
            const insertLine = lastImportLine >= 0 ? lastImportLine + 1 : 0;
            const insertPosition = { line: insertLine, character: 0 };

            const action: CodeAction = {
              title: `Import ${moduleName}`,
              kind: CodeActionKind.QuickFix,
              diagnostics: [diagnostic],
              edit: {
                changes: {
                  [`file://${htmlModuleFile}`]: [
                    TextEdit.insert(insertPosition, `  import ${moduleName}\n`),
                  ],
                },
              },
            };
            codeActions.push(action);
          }
        }
      }
    }

    // Fix: Invalid attribute value - suggest valid values
    if (diagnostic.code === 'component-invalid-attribute-value') {
      const match = diagnostic.message.match(/Expected one of: (.+)\.$/);
      if (match) {
        const validValuesStr = match[1];
        const validValues = validValuesStr.split(', ').map(v => v.replace(/"/g, ''));

        // Create a code action for each valid value
        for (const validValue of validValues) {
          const action: CodeAction = {
            title: `Change to "${validValue}"`,
            kind: CodeActionKind.QuickFix,
            diagnostics: [diagnostic],
            edit: {
              changes: {
                [params.textDocument.uri]: [
                  TextEdit.replace(diagnostic.range, `"${validValue}"`),
                ],
              },
            },
          };
          codeActions.push(action);
        }
      }
    }

    // Fix: Add :key to :for loop
    if (diagnostic.code === 'for-missing-key') {
      // Extract the :for attribute text
      const forAttrText = document.getText(diagnostic.range);

      // Extract the variable name from :for={item <- @items}
      const varMatch = forAttrText.match(/:for=\{([a-zA-Z_][a-zA-Z0-9_]*)\s*<-/);
      const itemVar = varMatch ? varMatch[1] : 'item';

      // Find the position to insert :key (right after :for attribute)
      const insertPosition = diagnostic.range.end;

      const action: CodeAction = {
        title: `Add :key={${itemVar}.id}`,
        kind: CodeActionKind.QuickFix,
        diagnostics: [diagnostic],
        edit: {
          changes: {
            [params.textDocument.uri]: [
              TextEdit.insert(insertPosition, ` :key={${itemVar}.id}`),
            ],
          },
        },
      };
      codeActions.push(action);
    }
  }

  return codeActions.length > 0 ? codeActions : null;
});

let definitionRequestId = 0;

connection.onDefinition(async (params): Promise<Definition | null> => {
  const perfTimer = new PerfTimer('onDefinition');
  const requestId = ++definitionRequestId;

  try {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      debugLog('definition', `[#${requestId}] Definition aborted: document not found`);
      perfTimer.stop({ result: 'document_not_found' });
      return null;
    }

    const text = document.getText();
    const offset = document.offsetAt(params.position);
    const uri = params.textDocument.uri;
    const filePath = URI.parse(uri).fsPath;
    const isElixirFile = uri.endsWith('.ex') || uri.endsWith('.exs');

    debugLog(
      'definition',
      `[#${requestId}] Definition start: file=${filePath} pos=${params.position.line + 1}:${params.position.character + 1}`
    );

  const lineStart = text.lastIndexOf('\n', offset - 1) + 1;
  const lineEnd = text.indexOf('\n', offset);
  const line = text.substring(lineStart, lineEnd === -1 ? text.length : lineEnd);
  const charInLine = offset - lineStart;
  const contextBefore = text.substring(Math.max(0, offset - 100), offset);

  // Check for route helper go-to-definition (Routes.user_path, etc.)
  const routeHelperMatch = contextBefore.match(/Routes\.([a-z_]+)_(path|url)/);
  if (routeHelperMatch) {
    const helperBase = routeHelperMatch[1];
    const routes = routerRegistry.findRoutesByHelper(helperBase);

    if (routes.length > 0) {
      const route = routes[0]; // Use first route for definition
      const targetUri = URI.file(route.filePath).toString();
      const targetPosition = Position.create(route.line - 1, 0);

      return Location.create(targetUri, Range.create(targetPosition, targetPosition));
    }
  }

  // Check for verified route go-to-definition (~p"/users")
  const verifiedRouteMatch = contextBefore.match(/~p"([^"]*)$/);
  if (verifiedRouteMatch) {
    const routePath = verifiedRouteMatch[1];
    const route = routerRegistry.findRouteByPath(routePath);

    if (route) {
      const targetUri = URI.file(route.filePath).toString();
      const targetPosition = Position.create(route.line - 1, 0);

      return Location.create(targetUri, Range.create(targetPosition, targetPosition));
    }
  }

  // Check for template go-to-definition in controller render calls
  if (isElixirFile && filePath.endsWith('_controller.ex')) {
    // Simpler approach: Find atom at cursor position, then check if in render context
    // 1. Find the word at cursor (including the : if present)
    let atomStart = offset;
    let atomEnd = offset;

    // Find start of atom (look backwards for : or start of word)
    while (atomStart > 0 && /[a-z0-9_:]/.test(text[atomStart - 1])) {
      atomStart--;
    }

    // Find end of atom (look forwards for end of word)
    while (atomEnd < text.length && /[a-z0-9_]/.test(text[atomEnd])) {
      atomEnd++;
    }

    const atomText = text.substring(atomStart, atomEnd);

    // Check if it's an atom (starts with :)
    const atomMatch = atomText.match(/^:([a-z_][a-z0-9_]*)$/);

    if (atomMatch) {
      const templateName = atomMatch[1];

      // Check if we're in a render call context (look back up to 200 chars)
      const contextBefore = text.substring(Math.max(0, atomStart - 200), atomStart);
      const isInRenderCall = /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*$/.test(contextBefore);

      if (isInRenderCall) {

      // Extract controller module from file content (to get full namespace)
      let controllerModule: string | null = null;
      const moduleMatch = text.match(/defmodule\s+([\w.]+Controller)\s+do/);
      if (moduleMatch) {
        controllerModule = moduleMatch[1]; // e.g., RaffleyWeb.PageController
      } else {
        // Fallback to file path extraction (no namespace)
        const fileMatch = filePath.match(/([a-z_]+)_controller\.ex$/);
        if (fileMatch) {
          const baseName = fileMatch[1];
          const pascalCase = baseName
            .split('_')
            .map(part => part.charAt(0).toUpperCase() + part.slice(1))
            .join('');
          controllerModule = `${pascalCase}Controller`;
        }
      }

      if (controllerModule) {
        const htmlModule = controllerModule.replace(/Controller$/, 'HTML');

        // Find template
        const template = templatesRegistry.getTemplateByModule(htmlModule, templateName, 'html');

        if (template) {
          const targetUri = URI.file(template.filePath).toString();

          // For embedded templates (def template_name(assigns)), try to find function definition
          if (template.filePath.endsWith('.ex')) {
            try {
              const templateContent = fs.readFileSync(template.filePath, 'utf-8');
              const funcMatch = templateContent.match(new RegExp(`def ${templateName}\\s*\\(`));
              if (funcMatch && funcMatch.index !== undefined) {
                const lines = templateContent.substring(0, funcMatch.index).split('\n');
                const targetLine = lines.length - 1;
                const targetPosition = Position.create(targetLine, 0);
                return Location.create(targetUri, Range.create(targetPosition, targetPosition));
              }
            } catch {
              // Fall back to file start if we can't read the file
            }
          }

          // For .heex files or fallback, jump to file start
          const targetPosition = Position.create(0, 0);
          return Location.create(targetUri, Range.create(targetPosition, targetPosition));
        }
      }
      }
    }
  }

  if (isElixirFile && !isInsideHEExSigil(text, offset)) {
    return null;
  }

  // Use async version to get accurate component usages from Elixir HEEx parser
  const usageStack = await getComponentUsageStackAsync(text, offset, filePath, filePath);

  console.log('[onDefinition] usageStack length:', usageStack.length);
  console.log('[onDefinition] Cursor offset:', offset);
  usageStack.forEach((usage, idx) => {
    console.log(`[onDefinition] Stack[${idx}]: ${usage.componentName}, nameStart=${usage.nameStart}, nameEnd=${usage.nameEnd}, openTagStart=${usage.openTagStart}, blockEnd=${usage.blockEnd}`);
    console.log(`[onDefinition]   Cursor in name range? ${offset >= usage.nameStart && offset <= usage.nameEnd}`);
    console.log(`[onDefinition]   Cursor in block range? ${offset >= usage.openTagStart && offset <= usage.blockEnd}`);
  });

  const slotContext = detectSlotAtPosition(line, charInLine);
  if (slotContext && usageStack.length > 0) {
    const parentUsage = usageStack[usageStack.length - 1];
    const parentComponent = componentsRegistry.resolveComponent(filePath, parentUsage.componentName, {
      moduleContext: parentUsage.moduleContext,
      fileContent: isElixirFile ? text : undefined,
    });
    if (parentComponent) {
      const slotLocation = createSlotLocation(parentComponent, slotContext.slotName) || createComponentLocation(parentComponent);
      if (slotLocation) {
        debugLog(
          'definition',
          `[#${requestId}] Slot <:${slotContext.slotName}> resolved to ${slotLocation.uri}:${slotLocation.range.start.line + 1}`
        );
        const slotLink = createSlotDefinitionLink(
          document,
          params.position,
          charInLine,
          slotContext.slotName,
          slotLocation
        );
        debugLog('definition', `[#${requestId}] Definition returning slot location`);
        return [slotLink];
      }
      debugLog(
        'definition',
        `Slot <:${slotContext.slotName}> missing explicit declaration; falling back to component ${parentComponent.moduleName}`
      );
    }
  }

  const componentUsage = findComponentUsageAtName(usageStack, offset) || findEnclosingComponentUsage(text, offset);
  if (!componentUsage) {
    console.log('[onDefinition] ❌ No component usage found');
    debugLog('definition', `[#${requestId}] No component usage found for request in ${filePath}`);
    debugLog('definition', `[#${requestId}] Definition returning null (no usage)`);
    return null;
  }

  console.log('[onDefinition] ✅ Found component usage:', componentUsage.componentName);
  console.log('[onDefinition] Component details:', {
    name: componentUsage.componentName,
    moduleContext: componentUsage.moduleContext,
    nameStart: componentUsage.nameStart,
    nameEnd: componentUsage.nameEnd
  });

  const cacheKey = `${filePath}:${componentUsage.componentName}`;
  const cached = getCachedDefinition(cacheKey);
  if (cached) {
    console.log('[onDefinition] ✅ Using cached definition');
    debugLog('definition', `[#${requestId}] Using cached definition for <.${componentUsage.componentName}> -> ${cached.uri}:${cached.range.start.line + 1}`);
    const cachedLink = createComponentDefinitionLink(document, componentUsage, cached);
    return [cachedLink];
  }

  console.log('[onDefinition] Calling componentsRegistry.resolveComponent...');
  const component = componentsRegistry.resolveComponent(filePath, componentUsage.componentName, {
    moduleContext: componentUsage.moduleContext,
    fileContent: isElixirFile ? text : undefined,
  });

  if (!component) {
    console.log('[onDefinition] ❌ componentsRegistry.resolveComponent returned null');
    console.log('[onDefinition] Looking for component:', componentUsage.componentName);
    console.log('[onDefinition] Module context:', componentUsage.moduleContext);
    const allComponents = componentsRegistry.getAllComponents();
    console.log('[onDefinition] Total components in registry:', allComponents.length);

    // Check if icon exists in registry
    const iconComponents = allComponents.filter(c => c.name === 'icon');
    console.log('[onDefinition] Found "icon" components in registry:', iconComponents.length);
    if (iconComponents.length > 0) {
      console.log('[onDefinition] icon component(s) details:');
      iconComponents.forEach(c => {
        console.log(`[onDefinition]   - name: ${c.name}, module: ${c.moduleName}, file: ${c.filePath}`);
      });
      console.log('[onDefinition] ⚠️ ISSUE: icon exists but resolveComponent returned null!');
    } else {
      console.log('[onDefinition] icon component NOT in registry');
      console.log('[onDefinition] Available components:', allComponents.map(c => c.name).slice(0, 10).join(', '), '...');
    }

    const totalComponents = componentsRegistry.getAllComponents().length;
    const allComponentNames = componentsRegistry.getAllComponents().map(c => c.name).join(', ');
    debugLog(
      'definition',
      `[#${requestId}] Unable to resolve component <.${componentUsage.componentName}> (module context: ${componentUsage.moduleContext ?? 'n/a'}) from ${filePath}`
    );
    debugLog(
      'definition',
      `[#${requestId}] Registry contains ${totalComponents} total components: ${totalComponents > 0 ? allComponentNames : '<empty>'}`
    );
    const fallback = findFallbackComponentLocation(filePath, componentUsage.componentName);
    if (fallback) {
      debugLog('definition', `[#${requestId}] Fallback resolved <.${componentUsage.componentName}> to ${fallback.uri}:${fallback.range.start.line + 1}`);
      cacheDefinition(cacheKey, fallback);
      const fallbackLink = createComponentDefinitionLink(document, componentUsage, fallback);
      return [fallbackLink];
    }
    debugLog('definition', `[#${requestId}] Definition returning null (component unresolved)`);
    return null;
  }

  console.log('[onDefinition] ✅ Component resolved successfully!');
  console.log('[onDefinition] Component info:', {
    name: component.name,
    moduleName: component.moduleName,
    filePath: component.filePath
  });

  const location = createComponentLocation(component);
  if (location) {
    console.log('[onDefinition] ✅ Location created:', location.uri);
    debugLog(
      'definition',
      `[#${requestId}] Component <.${component.name}> resolved to ${location.uri}:${location.range.start.line + 1}`
    );
    debugLog('definition', `[#${requestId}] Definition returning component location`);
    cacheDefinition(cacheKey, location);
    const link = createComponentDefinitionLink(document, componentUsage, location);
    console.log('[onDefinition] ✅ Definition link created, returning!');
    return [link];
  } else {
    console.log('[onDefinition] ❌ Failed to create location from component');
    debugLog(
      'definition',
      `[#${requestId}] Component <.${component.name}> resolved but location could not be derived (module ${component.moduleName})`
    );
    const fallback = findFallbackComponentLocation(filePath, componentUsage.componentName);
    if (fallback) {
      debugLog('definition', `[#${requestId}] Fallback resolved <.${componentUsage.componentName}> to ${fallback.uri}:${fallback.range.start.line + 1}`);
      cacheDefinition(cacheKey, fallback);
      const fallbackLink = createComponentDefinitionLink(document, componentUsage, fallback);
      return [fallbackLink];
    }
    debugLog('definition', `[#${requestId}] Definition returning null (no location)`);
  }
  return null;
  } finally {
    perfTimer.stop();
  }
});

// Custom request handlers for Tree View
connection.onRequest('phoenix/listSchemas', () => {
  const schemas = schemaRegistry.getAllSchemas();
  return schemas.map(schema => ({
    name: schema.moduleName,
    tableName: schema.tableName,
    filePath: schema.filePath,
    location: { line: Math.max(0, schema.line - 1), character: 0 }, // Convert to 0-based
    fieldsCount: schema.fields.length,
    associationsCount: schema.associationsDetailed.length,
    fields: schema.fields.map(field => ({
      name: field.name,
      type: field.type,
      elixirType: field.elixirType
    })),
    associations: schema.associationsDetailed.map(assoc => ({
      fieldName: assoc.fieldName,
      targetModule: assoc.targetModule,
      type: assoc.type
    }))
  }));
});

connection.onRequest('phoenix/listComponents', () => {
  const components = componentsRegistry.getAllComponents();
  return components.map(component => ({
    name: component.name,
    filePath: component.filePath,
    location: { line: Math.max(0, component.line - 1), character: 0 }, // Convert to 0-based
    attributesCount: component.attributes.length,
    slotsCount: component.slots.length,
    attributes: component.attributes.map(attr => ({
      name: attr.name,
      type: attr.type,
      required: attr.required,
      default: attr.default,
      values: attr.values,
      doc: attr.doc,
      rawType: attr.rawType
    })),
    slots: component.slots.map(slot => ({
      name: slot.name,
      required: slot.required,
      doc: slot.doc,
      attributes: slot.attributes.map(attr => ({
        name: attr.name,
        type: attr.type,
        required: attr.required,
        default: attr.default,
        values: attr.values,
        doc: attr.doc,
        rawType: attr.rawType
      }))
    }))
  }));
});

connection.onRequest('phoenix/listRoutes', () => {
  const routes = routerRegistry.getRoutes();
  return routes.map(route => ({
    verb: route.verb,
    path: route.path,
    controller: route.controller,
    action: route.action,
    liveModule: route.liveModule,
    liveAction: route.liveAction,
    filePath: route.filePath,
    location: { line: Math.max(0, route.line - 1), character: 0 }, // Convert to 0-based
    pipeline: route.pipeline,
    scopePath: route.scopePath
  }));
});

connection.onRequest('phoenix/listTemplates', () => {
  const templates = templatesRegistry.getAllTemplates();

  // Filter out components - only show actual templates from template files
  const actualTemplates = templates.filter(template => {
    const fileName = template.filePath.split('/').pop() || '';
    return fileName.endsWith('_html.ex') ||
           fileName.endsWith('_view.ex') ||
           fileName.endsWith('.heex');
  });

  return actualTemplates.map(template => ({
    name: template.name,
    format: template.format,
    filePath: template.filePath,
    location: { line: 0, character: 0 },
    module: template.moduleName
  }));
});

connection.onRequest('phoenix/listEvents', () => {
  const events = eventsRegistry.getAllEvents();
  return events.map(event => ({
    name: event.name,
    type: event.kind, // 'handle_event' or 'handle_info'
    filePath: event.filePath,
    location: { line: Math.max(0, event.line - 1), character: 0 } // Convert to 0-based
  }));
});

connection.onRequest('phoenix/listLiveView', () => {
  const modules = liveViewRegistry.getAllModules();
  return modules.map(module => ({
    module: module.module,
    filePath: module.filePath,
    functions: module.functions.map(func => ({
      name: func.name,
      type: func.type,
      eventName: func.event_name,
      location: { line: Math.max(0, func.line - 1), character: 0 }
    }))
  }));
});

// Make the text document manager listen on the connection
documents.listen(connection);

// Listen on the connection
connection.listen();
