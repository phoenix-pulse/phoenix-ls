import * as fs from 'fs';
import * as path from 'path';

export interface AssetInfo {
  // Public URL path (e.g., "/images/logo.svg")
  publicPath: string;
  // Absolute file system path
  filePath: string;
  // File size in bytes
  size: number;
  // File extension
  extension: string;
  // Asset type category
  type: 'image' | 'css' | 'js' | 'font' | 'other';
}

/**
 * Registry for static assets in /priv/static/
 * Provides completions for ~p"/images/..." paths
 */
export class AssetRegistry {
  private assets: AssetInfo[] = [];
  private workspaceRoot = '';
  private staticDir = '';

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
    this.staticDir = path.join(root, 'priv', 'static');
  }

  getAssets(): AssetInfo[] {
    return this.assets;
  }

  /**
   * Find assets matching a partial public path
   * Example: "/images/log" -> ["/images/logo.svg", "/images/logo-small.png"]
   */
  findAssetsByPath(partial: string): AssetInfo[] {
    const normalizedPartial = partial.toLowerCase();
    return this.assets.filter(asset =>
      asset.publicPath.toLowerCase().startsWith(normalizedPartial)
    );
  }

  /**
   * Get assets by directory prefix
   * Example: "/images/" -> all image assets
   */
  getAssetsByPrefix(prefix: string): AssetInfo[] {
    return this.assets.filter(asset => asset.publicPath.startsWith(prefix));
  }

  /**
   * Scan /priv/static/ directory for assets
   */
  scanWorkspace(workspaceRoot: string): void {
    this.setWorkspaceRoot(workspaceRoot);
    this.assets = [];

    if (!fs.existsSync(this.staticDir)) {
      console.log('[AssetRegistry] No /priv/static/ directory found');
      return;
    }

    const startTime = Date.now();
    this.scanDirectory(this.staticDir, '');
    const duration = Date.now() - startTime;

    console.log(`[AssetRegistry] Scan complete. Found ${this.assets.length} assets in ${duration}ms`);
  }

  private scanDirectory(dir: string, publicPrefix: string): void {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const publicPath = publicPrefix + '/' + entry.name;

        if (entry.isDirectory()) {
          // Recursively scan subdirectories
          this.scanDirectory(fullPath, publicPath);
        } else if (entry.isFile()) {
          // Skip cache manifest files
          if (entry.name === 'cache_manifest.json') {
            continue;
          }

          try {
            const stats = fs.statSync(fullPath);
            const extension = path.extname(entry.name).toLowerCase();
            const type = this.categorizeAsset(extension);

            this.assets.push({
              publicPath,
              filePath: fullPath,
              size: stats.size,
              extension,
              type,
            });
          } catch (err) {
            console.error(`[AssetRegistry] Error reading file ${fullPath}:`, err);
          }
        }
      }
    } catch (err) {
      console.error(`[AssetRegistry] Error scanning directory ${dir}:`, err);
    }
  }

  private categorizeAsset(extension: string): AssetInfo['type'] {
    // Image extensions
    if (['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico', '.bmp'].includes(extension)) {
      return 'image';
    }

    // CSS extensions
    if (['.css', '.scss', '.sass', '.less'].includes(extension)) {
      return 'css';
    }

    // JavaScript extensions
    if (['.js', '.mjs', '.jsx', '.ts', '.tsx'].includes(extension)) {
      return 'js';
    }

    // Font extensions
    if (['.woff', '.woff2', '.ttf', '.otf', '.eot'].includes(extension)) {
      return 'font';
    }

    return 'other';
  }

  /**
   * Update assets when files change
   */
  updateFile(filePath: string): void {
    // Remove old asset if it exists
    this.assets = this.assets.filter(asset => asset.filePath !== filePath);

    // If file still exists, add it back
    if (fs.existsSync(filePath)) {
      try {
        const stats = fs.statSync(filePath);
        const extension = path.extname(filePath).toLowerCase();
        const type = this.categorizeAsset(extension);

        // Calculate public path
        const relativePath = path.relative(this.staticDir, filePath);
        const publicPath = '/' + relativePath.replace(/\\/g, '/');

        this.assets.push({
          publicPath,
          filePath,
          size: stats.size,
          extension,
          type,
        });
      } catch (err) {
        console.error(`[AssetRegistry] Error updating file ${filePath}:`, err);
      }
    }
  }

  /**
   * Remove asset when file is deleted
   */
  removeFile(filePath: string): void {
    this.assets = this.assets.filter(asset => asset.filePath !== filePath);
  }
}
