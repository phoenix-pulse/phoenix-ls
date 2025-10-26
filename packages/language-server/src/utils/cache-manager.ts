import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';

export interface CacheData {
  version: string;
  timestamp: number;
  workspaceRoot: string;
  registries: {
    components?: any;
    schemas?: any;
    events?: any;
    routes?: any;
    controllers?: any;
    templates?: any;
    liveview?: any;
  };
  fileHashes: Record<string, string>;
}

export class CacheManager {
  private static readonly CACHE_VERSION = '1.0.0';
  private static readonly CACHE_FILENAME = '.phoenix-pulse-cache.json';

  /**
   * Get the cache file path for a workspace
   */
  static getCachePath(workspaceRoot: string): string {
    const vscodeDir = path.join(workspaceRoot, '.vscode');
    return path.join(vscodeDir, this.CACHE_FILENAME);
  }

  /**
   * Load cache from disk
   */
  static async loadCache(workspaceRoot: string): Promise<CacheData | null> {
    const cachePath = this.getCachePath(workspaceRoot);

    try {
      if (!fs.existsSync(cachePath)) {
        console.log('[CacheManager] No cache file found');
        return null;
      }

      const content = fs.readFileSync(cachePath, 'utf-8');
      const cache: CacheData = JSON.parse(content);

      // Validate version
      if (cache.version !== this.CACHE_VERSION) {
        console.log(`[CacheManager] Cache version mismatch (cache: ${cache.version}, current: ${this.CACHE_VERSION})`);
        return null;
      }

      // Validate workspace root
      if (cache.workspaceRoot !== workspaceRoot) {
        console.log('[CacheManager] Workspace root mismatch');
        return null;
      }

      console.log(`[CacheManager] Cache loaded successfully (age: ${Math.round((Date.now() - cache.timestamp) / 1000)}s)`);
      return cache;
    } catch (error) {
      console.log(`[CacheManager] Failed to load cache: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  /**
   * Save cache to disk
   */
  static async saveCache(workspaceRoot: string, cacheData: CacheData): Promise<void> {
    const cachePath = this.getCachePath(workspaceRoot);

    try {
      // Ensure .vscode directory exists
      const vscodeDir = path.dirname(cachePath);
      if (!fs.existsSync(vscodeDir)) {
        fs.mkdirSync(vscodeDir, { recursive: true });
      }

      cacheData.version = this.CACHE_VERSION;
      cacheData.timestamp = Date.now();
      cacheData.workspaceRoot = workspaceRoot;

      const content = JSON.stringify(cacheData, null, 2);
      fs.writeFileSync(cachePath, content, 'utf-8');

      console.log(`[CacheManager] Cache saved successfully (${(content.length / 1024).toFixed(1)}KB)`);
    } catch (error) {
      console.log(`[CacheManager] Failed to save cache: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Validate cache freshness by checking file modification times
   */
  static async validateCacheFreshness(
    workspaceRoot: string,
    cache: CacheData,
    filesToCheck: string[]
  ): Promise<boolean> {
    try {
      for (const filePath of filesToCheck) {
        if (!fs.existsSync(filePath)) {
          continue;
        }

        const stats = fs.statSync(filePath);
        const mtime = stats.mtimeMs;

        // If any file is newer than cache, invalidate
        if (mtime > cache.timestamp) {
          console.log(`[CacheManager] Cache invalidated - ${path.relative(workspaceRoot, filePath)} was modified`);
          return false;
        }
      }

      console.log(`[CacheManager] Cache is fresh (checked ${filesToCheck.length} files)`);
      return true;
    } catch (error) {
      console.log(`[CacheManager] Cache validation failed: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  /**
   * Delete cache file
   */
  static async clearCache(workspaceRoot: string): Promise<void> {
    const cachePath = this.getCachePath(workspaceRoot);

    try {
      if (fs.existsSync(cachePath)) {
        fs.unlinkSync(cachePath);
        console.log('[CacheManager] Cache cleared');
      }
    } catch (error) {
      console.log(`[CacheManager] Failed to clear cache: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Collect all relevant files for cache validation
   */
  static collectFilesForValidation(workspaceRoot: string): string[] {
    const files: string[] = [];

    const scanDirectory = (dir: string, pattern: RegExp) => {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);

          if (entry.isDirectory()) {
            const dirName = entry.name;
            if (dirName === 'node_modules' || dirName === 'deps' ||
                dirName === '_build' || dirName === '.git' ||
                dirName === 'assets') {
              continue;
            }
            scanDirectory(fullPath, pattern);
          } else if (entry.isFile() && pattern.test(entry.name)) {
            files.push(fullPath);
          }
        }
      } catch (err) {
        // Ignore directories we can't read
      }
    };

    // Scan for all Elixir files that our registries care about
    scanDirectory(workspaceRoot, /\.(ex|exs|heex)$/);

    return files;
  }
}
