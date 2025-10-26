import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { PerfTimer } from './utils/perf';
import {
  parseElixirLiveView,
  isLiveViewMetadata,
  isLiveViewError,
  isElixirAvailable,
  type LiveViewMetadata,
  type LiveViewFunctionInfo,
} from './parsers/elixir-ast-parser';

export interface PhoenixLiveViewModule {
  module: string;
  filePath: string;
  functions: LiveViewFunctionInfo[];
}

export class LiveViewRegistry {
  private liveViews: Map<string, PhoenixLiveViewModule> = new Map(); // normalized filePath -> module
  private workspaceRoot: string = '';
  private fileHashes: Map<string, string> = new Map();
  private useElixirParser: boolean = true;
  private elixirAvailable: boolean | null = null;

  constructor() {
    // Allow disabling Elixir parser via environment variable
    const envVar = process.env.PHOENIX_PULSE_USE_REGEX_PARSER;
    if (envVar === 'true' || envVar === '1') {
      this.useElixirParser = false;
      console.log('[LiveViewRegistry] Elixir parser disabled via PHOENIX_PULSE_USE_REGEX_PARSER');
    }
  }

  private normalizePath(filePath: string): string {
    return path.normalize(filePath);
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
  }

  getWorkspaceRoot(): string {
    return this.workspaceRoot;
  }

  /**
   * Parse file with Elixir parser
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<PhoenixLiveViewModule | null> {
    // Check if we should use Elixir parser
    if (!this.useElixirParser) {
      return null;
    }

    // Check Elixir availability (cached after first check)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (!this.elixirAvailable) {
        console.log('[LiveViewRegistry] Elixir not available, cannot parse LiveView files');
      }
    }

    if (!this.elixirAvailable) {
      return null;
    }

    const normalizedPath = this.normalizePath(filePath);
    const timer = new PerfTimer('liveview.parseFileWithElixir');

    try {
      const result = await parseElixirLiveView(normalizedPath, false);

      if (isLiveViewError(result)) {
        console.log(
          `[LiveViewRegistry] Elixir parser failed for ${path.relative(this.workspaceRoot || '', normalizedPath)}: ${result.message}`
        );
        return null;
      }

      if (isLiveViewMetadata(result)) {
        if (!result.module || result.functions.length === 0) {
          // Skip files without a module or functions
          return null;
        }

        const module: PhoenixLiveViewModule = {
          module: result.module,
          filePath: normalizedPath,
          functions: result.functions
        };

        timer.stop({
          file: path.relative(this.workspaceRoot || '', normalizedPath),
          functions: result.functions.length,
          parser: 'elixir',
        });
        return module;
      }

      return null;
    } catch (error) {
      console.log(
        `[LiveViewRegistry] Elixir parser exception for ${path.relative(this.workspaceRoot || '', normalizedPath)}: ${error instanceof Error ? error.message : String(error)}`
      );
      return null;
    }
  }

  /**
   * Parse file async
   */
  async parseFileAsync(filePath: string, content: string): Promise<PhoenixLiveViewModule | null> {
    return this.parseFileWithElixir(filePath, content);
  }

  /**
   * Update LiveView module for a specific file
   */
  async updateFile(filePath: string, content: string) {
    const normalizedPath = this.normalizePath(filePath);
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previousHash = this.fileHashes.get(normalizedPath);

    if (previousHash === hash && this.liveViews.has(normalizedPath)) {
      return;
    }

    const timer = new PerfTimer('liveview.updateFile');
    const module = await this.parseFileAsync(normalizedPath, content);

    if (module) {
      this.liveViews.set(normalizedPath, module);
    } else {
      // Remove if parsing failed or no functions found
      this.liveViews.delete(normalizedPath);
    }

    this.fileHashes.set(normalizedPath, hash);

    timer.stop({
      file: path.relative(this.workspaceRoot || '', normalizedPath),
      functions: module?.functions.length || 0
    });
  }

  /**
   * Remove a file from the registry
   */
  removeFile(filePath: string) {
    const normalizedPath = this.normalizePath(filePath);
    this.liveViews.delete(normalizedPath);
    this.fileHashes.delete(normalizedPath);
  }

  /**
   * Get all LiveView modules
   */
  getAllModules(): PhoenixLiveViewModule[] {
    return Array.from(this.liveViews.values());
  }

  /**
   * Get LiveView module by file path
   */
  getModuleByFile(filePath: string): PhoenixLiveViewModule | null {
    const normalizedPath = this.normalizePath(filePath);
    return this.liveViews.get(normalizedPath) || null;
  }

  /**
   * Scan workspace for LiveView files
   */
  async scanWorkspace(workspaceRoot: string): Promise<void> {
    this.workspaceRoot = workspaceRoot;

    // Collect all *_live.ex files
    const filesToParse: Array<{ path: string; content: string }> = [];

    const scanDirectory = (dir: string) => {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);

          // Skip common excluded directories
          if (entry.isDirectory()) {
            const dirName = entry.name;
            if (dirName === 'node_modules' || dirName === 'deps' ||
                dirName === '_build' || dirName === '.git' ||
                dirName === 'assets') {
              continue;
            }
            scanDirectory(fullPath);
          } else if (entry.isFile() && (entry.name.endsWith('.ex') || entry.name.endsWith('.exs'))) {
            // Parse LiveView files:
            // 1. Files ending with *_live.ex
            // 2. .ex files inside folders ending with _live/
            const isLiveViewFile = entry.name.endsWith('_live.ex');
            const parentDirName = path.basename(dir);
            const isInLiveFolder = parentDirName.endsWith('_live');

            if (!isLiveViewFile && !isInLiveFolder) {
              continue;
            }
            try {
              const content = fs.readFileSync(fullPath, 'utf-8');
              filesToParse.push({ path: fullPath, content });
            } catch (err) {
              // Ignore files we can't read
            }
          }
        }
      } catch (err) {
        // Ignore directories we can't read
      }
    };

    // Collect files
    scanDirectory(workspaceRoot);

    // Check Elixir availability once before parallel parsing
    if (this.useElixirParser && this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[LiveViewRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[LiveViewRegistry] Elixir not available, skipping LiveView parsing');
      }
    }

    // Parse all files asynchronously
    const parseTimer = new PerfTimer('liveview.scanWorkspace');
    const parsePromises = filesToParse.map(async ({ path: filePath, content }) => {
      try {
        const module = await this.parseFileAsync(filePath, content);
        const normalizedPath = this.normalizePath(filePath);
        const hash = crypto.createHash('sha1').update(content).digest('hex');

        if (module) {
          this.liveViews.set(normalizedPath, module);
        }
        this.fileHashes.set(normalizedPath, hash);
      } catch (err) {
        // Ignore parse errors for individual files
        console.log(`[LiveViewRegistry] Failed to parse ${filePath}: ${err instanceof Error ? err.message : String(err)}`);
      }
    });

    await Promise.all(parsePromises);

    const totalModules = Array.from(this.liveViews.values()).length;
    const totalFunctions = Array.from(this.liveViews.values()).reduce((sum, m) => sum + m.functions.length, 0);

    parseTimer.stop({
      root: workspaceRoot,
      files: filesToParse.length,
      modules: totalModules,
      functions: totalFunctions,
    });
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const liveViewsArray: Array<[string, PhoenixLiveViewModule]> = this.liveViews ? Array.from(this.liveViews.entries()) : [];
    const fileHashesObj: Record<string, string> = {};

    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        fileHashesObj[filePath] = hash;
      }
    }

    return {
      liveViews: liveViewsArray,
      fileHashes: fileHashesObj,
      workspaceRoot: this.workspaceRoot,
    };
  }

  /**
   * Deserialize registry data from cache
   */
  loadFromCache(cacheData: any): void {
    if (!cacheData) {
      return;
    }

    // Clear current data
    if (this.liveViews) this.liveViews.clear();
    if (this.fileHashes) this.fileHashes.clear();

    // Load LiveView modules
    if (cacheData.liveViews && Array.isArray(cacheData.liveViews)) {
      for (const [filePath, module] of cacheData.liveViews) {
        this.liveViews.set(filePath, module);
      }
    }

    // Load file hashes
    if (cacheData.fileHashes) {
      for (const [filePath, hash] of Object.entries(cacheData.fileHashes)) {
        this.fileHashes.set(filePath, hash as string);
      }
    }

    // Load workspace root
    if (cacheData.workspaceRoot) {
      this.workspaceRoot = cacheData.workspaceRoot;
    }

    const totalModules = this.liveViews?.size || 0;
    const totalFunctions = this.liveViews
      ? Array.from(this.liveViews.values()).reduce((sum, m) => sum + m.functions.length, 0)
      : 0;
    console.log(`[LiveViewRegistry] Loaded ${totalModules} modules with ${totalFunctions} functions from cache`);
  }
}
