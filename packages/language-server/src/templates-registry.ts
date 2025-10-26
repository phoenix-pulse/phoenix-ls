import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { PerfTimer } from './utils/perf';
import {
  parseElixirTemplate,
  isTemplateMetadata,
  TemplateMetadata,
  isElixirAvailable
} from './parsers/elixir-ast-parser';

export interface TemplateInfo {
  moduleName: string;
  name: string;
  format: string;
  filePath: string;
}

/**
 * Registry for Phoenix templates (file-based and embedded)
 *
 * KNOWN LIMITATION: This registry assumes ONE module per file.
 * Files with multiple modules (rare in Phoenix) will only register
 * the first module's templates. Fixing this requires architectural
 * changes to moduleByFile (Map<string, string> -> Map<string, string[]>)
 * and updateFile/removeFile logic.
 */
export class TemplatesRegistry {
  private templatesByModule = new Map<string, TemplateInfo[]>();
  private templatesByPath = new Map<string, TemplateInfo>();
  private moduleByFile = new Map<string, string>(); // LIMITATION: Only stores ONE module per file
  private fileHashes = new Map<string, string>();
  private workspaceRoot = '';
  private useElixirParser: boolean = true;
  private elixirAvailable: boolean | null = null;

  constructor() {
    // Check environment variable to optionally disable Elixir parser
    const envVar = process.env.PHOENIX_PULSE_USE_REGEX_PARSER;
    if (envVar === 'true' || envVar === '1') {
      this.useElixirParser = false;
      console.log('[TemplatesRegistry] Using regex parser (PHOENIX_PULSE_USE_REGEX_PARSER=true)');
    }
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
  }

  getTemplateByModule(moduleName: string, name: string, format?: string): TemplateInfo | null {
    const templates = this.templatesByModule.get(moduleName);
    if (!templates) {
      return null;
    }

    const normalizedName = name.trim();
    const preferredFormat = format ? format.trim() : undefined;

    let candidate: TemplateInfo | null = null;

    for (const template of templates) {
      if (template.name !== normalizedName) {
        continue;
      }

      if (preferredFormat) {
        if (template.format === preferredFormat) {
          return template;
        }
        // Keep track of the first candidate if exact format not found yet
        candidate = candidate ?? template;
      } else {
        // Prefer html when format unspecified
        if (template.format === 'html') {
          return template;
        }
        candidate = candidate ?? template;
      }
    }

    return candidate;
  }

  getTemplateByPath(filePath: string): TemplateInfo | null {
    return this.templatesByPath.get(filePath) || null;
  }

  getTemplatesForModule(moduleName: string): TemplateInfo[] {
    return this.templatesByModule.get(moduleName) ?? [];
  }

  getModuleNameForFile(filePath: string): string | null {
    const normalized = path.normalize(filePath);
    return this.moduleByFile.get(normalized) ?? null;
  }

  getAllTemplates(): TemplateInfo[] {
    return Array.from(this.templatesByPath.values());
  }

  /**
   * Parse file with Elixir AST parser and convert to TemplateInfo array
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<TemplateInfo[] | null> {
    // Check if we should use Elixir parser
    if (!this.useElixirParser) {
      return null;
    }

    // Check Elixir availability (cached)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[TemplatesRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[TemplatesRegistry] Elixir not available - using regex parser');
      }
    }

    if (!this.elixirAvailable) {
      return null;
    }

    // Verbose log removed - happens before cache check, misleading
    // Cache hits are silent, actual parsing is logged by parseElixirTemplate() if needed

    try {
      const result = await parseElixirTemplate(filePath);

      if (isTemplateMetadata(result)) {
        return this.convertElixirToTemplateInfo(filePath, content, result);
      } else {
        console.error(`[TemplatesRegistry] Elixir parser error for ${filePath}:`, result.message);
        return null;
      }
    } catch (error) {
      console.error(`[TemplatesRegistry] Elixir parser failed for ${filePath}:`, error);
      return null;
    }
  }

  /**
   * Convert Elixir parser metadata to TemplateInfo array
   */
  private convertElixirToTemplateInfo(
    filePath: string,
    content: string,
    metadata: TemplateMetadata
  ): TemplateInfo[] {
    const moduleName = metadata.module || this.extractModuleName(content);
    if (!moduleName) {
      return [];
    }

    const templates: TemplateInfo[] = [];

    // 1. Process embed_templates patterns
    for (const pattern of metadata.embed_templates) {
      const embeddedTemplates = this.extractEmbeddedTemplatesFromPattern(
        filePath,
        pattern,
        moduleName
      );
      templates.push(...embeddedTemplates);
    }

    // 2. Process module type (:view or :html) for directory-based templates
    if (metadata.module_type === 'view') {
      const viewTemplates = this.extractViewTemplates(filePath, content, moduleName);
      templates.push(...viewTemplates);
    } else if (metadata.module_type === 'html') {
      const htmlTemplates = this.extractHtmlTemplatesFromDirectory(filePath, moduleName);
      templates.push(...htmlTemplates);
    }

    // 3. Process function templates
    for (const funcTemplate of metadata.function_templates) {
      // Create unique filePath for function templates to avoid collisions in templatesByPath
      // Use format: /path/to/file.ex#template_name
      const uniqueFilePath = `${filePath}#${funcTemplate.name}`;

      templates.push({
        moduleName,
        name: funcTemplate.name,
        format: funcTemplate.format,
        filePath: uniqueFilePath,
      });
    }

    // Deduplicate by name+format
    const uniqueTemplates = new Map<string, TemplateInfo>();
    for (const template of templates) {
      const key = `${template.name}:${template.format}`;
      if (!uniqueTemplates.has(key)) {
        uniqueTemplates.set(key, template);
      }
    }

    return Array.from(uniqueTemplates.values());
  }

  /**
   * Extract templates from embed_templates pattern
   */
  private extractEmbeddedTemplatesFromPattern(
    filePath: string,
    pattern: string,
    moduleName: string
  ): TemplateInfo[] {
    const templates: TemplateInfo[] = [];
    const templateDir = this.resolvePatternDirectory(filePath, pattern);
    if (!templateDir) {
      return templates;
    }

    const files = this.readTemplateFiles(templateDir);
    for (const file of files) {
      const info = this.buildTemplateInfo(moduleName, file);
      if (info) {
        templates.push(info);
      }
    }

    return templates;
  }

  /**
   * Extract HTML templates from directory (Phoenix 1.7+)
   */
  private extractHtmlTemplatesFromDirectory(
    filePath: string,
    moduleName: string
  ): TemplateInfo[] {
    const templates: TemplateInfo[] = [];
    const templatesDir = this.resolveHtmlTemplatesDirectory(filePath);
    if (templatesDir && fs.existsSync(templatesDir)) {
      const files = this.readTemplateFiles(templatesDir);
      for (const file of files) {
        const info = this.buildTemplateInfo(moduleName, file);
        if (info) {
          templates.push(info);
        }
      }
    }
    return templates;
  }

  /**
   * Parse file (tries Elixir parser first, falls back to regex)
   */
  private async parseFileAsync(filePath: string, content: string): Promise<TemplateInfo[]> {
    // Try Elixir parser first
    const elixirResult = await this.parseFileWithElixir(filePath, content);
    if (elixirResult !== null) {
      return elixirResult;
    }

    // Fall back to regex parser
    return this.parseFileSync(filePath, content);
  }

  /**
   * Synchronous regex-based parsing (original implementation)
   */
  private parseFileSync(filePath: string, content: string): TemplateInfo[] {
    const moduleName = this.extractModuleName(content);
    if (!moduleName) {
      return [];
    }

    const embeddedTemplates = this.extractEmbeddedTemplates(filePath, content, moduleName);
    const viewTemplates = this.extractViewTemplates(filePath, content, moduleName);
    const htmlTemplates = this.extractHtmlTemplates(filePath, content, moduleName);

    // Deduplicate templates by name+format
    const allTemplates = [...embeddedTemplates, ...viewTemplates, ...htmlTemplates];
    const uniqueTemplates = new Map<string, TemplateInfo>();
    for (const template of allTemplates) {
      const key = `${template.name}:${template.format}`;
      if (!uniqueTemplates.has(key)) {
        uniqueTemplates.set(key, template);
      }
    }

    return Array.from(uniqueTemplates.values());
  }

  async updateFile(filePath: string, content: string) {
    const normalizedPath = path.normalize(filePath);
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previousHash = this.fileHashes.get(normalizedPath);
    if (previousHash === hash) {
      return;
    }

    const timer = new PerfTimer('templates.updateFile');

    // Parse using async method (tries Elixir first, falls back to regex)
    const templates = await this.parseFileAsync(normalizedPath, content);

    if (templates.length === 0) {
      timer.stop({ file: path.relative(this.workspaceRoot || '', normalizedPath), templates: 0 });
      return;
    }

    // Get module name from first template (all templates share same module)
    const moduleName = templates[0]?.moduleName;
    if (!moduleName) {
      timer.stop({ file: path.relative(this.workspaceRoot || '', normalizedPath), templates: 0 });
      return;
    }

    // Atomic swap - remove old and add new immediately
    // Race window reduced from 10-50ms to <1ms
    this.removeFile(normalizedPath);

    this.templatesByModule.set(moduleName, templates);
    for (const template of templates) {
      this.templatesByPath.set(template.filePath, template);
    }
    this.moduleByFile.set(normalizedPath, moduleName);

    this.fileHashes.set(normalizedPath, hash);
    timer.stop({ file: path.relative(this.workspaceRoot || '', normalizedPath), templates: templates.length });
  }

  removeFile(filePath: string) {
    const normalizedPath = path.normalize(filePath);
    const moduleName = this.moduleByFile.get(normalizedPath);
    if (!moduleName) {
      this.fileHashes.delete(normalizedPath);
      return;
    }

    const templates = this.templatesByModule.get(moduleName) ?? [];
    for (const template of templates) {
      this.templatesByPath.delete(template.filePath);
    }
    this.templatesByModule.delete(moduleName);
    this.moduleByFile.delete(normalizedPath);

    this.fileHashes.delete(normalizedPath);
  }

  async scanWorkspace(workspaceRoot: string) {
    this.workspaceRoot = workspaceRoot;

    // Collect all .ex files first
    const filesToParse: Array<{ path: string; content: string }> = [];

    const scan = (dir: string) => {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);
          if (entry.isDirectory()) {
            if (this.shouldSkipDir(entry.name)) {
              continue;
            }
            scan(fullPath);
          } else if (entry.isFile() && entry.name.endsWith('.ex')) {
            // Skip files that will never have templates (performance optimization)
            if (this.shouldSkipTemplateFile(entry.name, fullPath)) {
              continue;
            }
            try {
              const content = fs.readFileSync(fullPath, 'utf-8');
              filesToParse.push({ path: fullPath, content });
            } catch {
              // ignore
            }
          }
        }
      } catch {
        // ignore
      }
    };

    const timer = new PerfTimer('templates.scanWorkspace');
    scan(workspaceRoot);

    // Check Elixir availability once before parallel parsing
    // This prevents race condition where all parallel parses check simultaneously
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[TemplatesRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[TemplatesRegistry] Elixir not available - using regex parser');
      }
    }

    // Parse all files in parallel
    const parsePromises = filesToParse.map(async ({ path: filePath, content }) => {
      const normalizedPath = path.normalize(filePath);
      const hash = crypto.createHash('sha1').update(content).digest('hex');
      const templates = await this.parseFileAsync(normalizedPath, content);

      if (templates.length === 0) {
        return;
      }

      const moduleName = templates[0]?.moduleName;
      if (!moduleName) {
        return;
      }

      // Update maps (safe because each file is processed in its own promise)
      this.templatesByModule.set(moduleName, templates);
      for (const template of templates) {
        this.templatesByPath.set(template.filePath, template);
      }
      this.moduleByFile.set(normalizedPath, moduleName);
      this.fileHashes.set(normalizedPath, hash);
    });

    await Promise.all(parsePromises);

    timer.stop({ templates: this.templatesByPath.size });
  }

  private shouldSkipDir(name: string): boolean {
    return ['deps', '_build', 'node_modules', '.git', 'priv', 'assets', 'components'].includes(name);
  }

  private shouldSkipTemplateFile(fileName: string, fullPath: string): boolean {
    // Skip config/infrastructure files that never have templates
    const skipFiles = [
      'application.ex', 'repo.ex', 'mailer.ex', 'endpoint.ex',
      'gettext.ex', 'telemetry.ex', 'router.ex', 'mix.exs'
    ];
    if (skipFiles.includes(fileName)) {
      return true;
    }

    // Skip test helper files
    if (fileName.endsWith('_case.ex')) {
      return true;
    }

    // Skip JSON renderers (only care about HTML templates)
    if (fileName.endsWith('_json.ex')) {
      return true;
    }

    // Skip context/schema files (lib/app_name/*.ex but not lib/app_name_web/*.ex)
    // These are usually contexts like Accounts, Catalog, etc.
    if (fullPath.includes(`${path.sep}lib${path.sep}`) && !fullPath.includes(`_web${path.sep}`)) {
      const segments = fullPath.split(path.sep);
      const libIndex = segments.findIndex(s => s === 'lib');
      // If it's directly under lib/app_name/*.ex (depth 2), it's likely a context/schema
      if (libIndex >= 0 && segments.length - libIndex === 3 && !fileName.endsWith('_live.ex')) {
        return true;
      }
    }

    return false;
  }

  /**
   * Extract module name from file content
   *
   * LIMITATION: Only extracts the FIRST defmodule in the file.
   * Multi-module files will only have their first module's templates registered.
   */
  private extractModuleName(content: string): string | null {
    const match = content.match(/defmodule\s+([\w.]+)\s+do/);
    return match ? match[1] : null;
  }

  private extractEmbeddedTemplates(filePath: string, content: string, moduleName: string): TemplateInfo[] {
    const templates: TemplateInfo[] = [];
    const embedPattern = /embed_templates\s+"([^"]+)"/g;
    let match: RegExpExecArray | null;

    while ((match = embedPattern.exec(content)) !== null) {
      const pattern = match[1];
      const templateDir = this.resolvePatternDirectory(filePath, pattern);
      if (!templateDir) {
        continue;
      }

      const files = this.readTemplateFiles(templateDir);
      for (const file of files) {
        const info = this.buildTemplateInfo(moduleName, file);
        if (info) {
          templates.push(info);
        }
      }
    }

    return templates;
  }

  private extractViewTemplates(filePath: string, content: string, moduleName: string): TemplateInfo[] {
    // Only attempt for modules using ... :view
    if (!/:view\b/.test(content)) {
      return [];
    }

    const templatesDir = this.resolveViewTemplatesDirectory(filePath);
    if (!templatesDir || !fs.existsSync(templatesDir)) {
      return [];
    }

    const files = this.readTemplateFiles(templatesDir);
    const templates: TemplateInfo[] = [];
    for (const file of files) {
      const info = this.buildTemplateInfo(moduleName, file);
      if (info) {
        templates.push(info);
      }
    }

    return templates;
  }

  private extractHtmlTemplates(filePath: string, content: string, moduleName: string): TemplateInfo[] {
    // Only attempt for modules using ... :html (Phoenix 1.7+)
    if (!/:html\b/.test(content)) {
      return [];
    }

    const templates: TemplateInfo[] = [];

    // 1. Check for templates in directory (page_html/ folder)
    const templatesDir = this.resolveHtmlTemplatesDirectory(filePath);
    if (templatesDir && fs.existsSync(templatesDir)) {
      const files = this.readTemplateFiles(templatesDir);
      for (const file of files) {
        const info = this.buildTemplateInfo(moduleName, file);
        if (info) {
          templates.push(info);
        }
      }
    }

    // 2. Check for embedded function templates (def template_name(assigns))
    const functionTemplates = this.extractFunctionTemplates(filePath, content, moduleName);
    templates.push(...functionTemplates);

    return templates;
  }

  private extractFunctionTemplates(filePath: string, content: string, moduleName: string): TemplateInfo[] {
    const templates: TemplateInfo[] = [];
    // Match: def template_name(assigns) do
    const functionPattern = /^\s*def\s+([a-z_][a-z0-9_]*)\s*\(\s*assigns\s*\)\s+do/gm;
    let match: RegExpExecArray | null;

    while ((match = functionPattern.exec(content)) !== null) {
      const templateName = match[1];

      // Skip private functions and special names
      if (templateName.startsWith('_') || ['render', 'sigil_H'].includes(templateName)) {
        continue;
      }

      // Create unique filePath for function templates to avoid collisions
      const uniqueFilePath = `${filePath}#${templateName}`;

      templates.push({
        moduleName,
        name: templateName,
        format: 'html',
        filePath: uniqueFilePath,
      });
    }

    return templates;
  }

  private resolvePatternDirectory(filePath: string, pattern: string): string | null {
    const dirName = path.dirname(filePath);

    if (!pattern.includes('*')) {
      const fullPath = path.resolve(dirName, pattern);
      return fs.existsSync(fullPath) ? fullPath : null;
    }

    const starIndex = pattern.indexOf('*');
    const base = pattern.slice(0, starIndex);
    const fullBase = path.resolve(dirName, base);
    return fs.existsSync(fullBase) ? fullBase : null;
  }

  private resolveViewTemplatesDirectory(filePath: string): string | null {
    const dir = path.dirname(filePath);
    const parentDir = path.dirname(dir);
    const baseName = path.basename(filePath, path.extname(filePath)); // e.g., user_view
    const viewName = baseName.replace(/_view$/, '');
    if (!viewName) {
      return null;
    }

    const candidate = path.join(parentDir, 'templates', viewName);
    return candidate;
  }

  private resolveHtmlTemplatesDirectory(filePath: string): string | null {
    // For Phoenix 1.7+ HTML modules
    // page_html.ex → page_html/ directory in same folder
    const dir = path.dirname(filePath);
    const baseName = path.basename(filePath, path.extname(filePath)); // e.g., page_html

    // Must end with _html to be valid
    if (!baseName.endsWith('_html')) {
      return null;
    }

    const candidate = path.join(dir, baseName);
    return candidate;
  }

  private readTemplateFiles(dir: string): string[] {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      const files: string[] = [];

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isFile()) {
          if (this.isTemplateFile(entry.name)) {
            files.push(fullPath);
          }
        } else if (entry.isDirectory()) {
          files.push(...this.readTemplateFiles(fullPath));
        }
      }

      return files;
    } catch {
      return [];
    }
  }

  private isTemplateFile(fileName: string): boolean {
    return /\.(heex|leex|eex)$/.test(fileName);
  }

  private buildTemplateInfo(moduleName: string, filePath: string): TemplateInfo | null {
    const baseName = path.basename(filePath);
    const withoutExt = baseName.replace(/\.(heex|leex|eex)$/, '');
    if (!withoutExt) {
      return null;
    }

    let format = 'html';
    let name = withoutExt;

    const parts = withoutExt.split('.');
    if (parts.length > 1) {
      format = parts.pop() || 'html';
      name = parts.join('.');
    }

    return {
      moduleName,
      name,
      format,
      filePath,
    };
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const templatesByModuleArray: Array<[string, TemplateInfo[]]> = this.templatesByModule ? Array.from(this.templatesByModule.entries()) : [];
    const templatesByPathArray: Array<[string, TemplateInfo]> = this.templatesByPath ? Array.from(this.templatesByPath.entries()) : [];
    const moduleByFileArray: Array<[string, string]> = this.moduleByFile ? Array.from(this.moduleByFile.entries()) : [];
    const fileHashesObj: Record<string, string> = {};

    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        fileHashesObj[filePath] = hash;
      }
    }

    return {
      templatesByModule: templatesByModuleArray,
      templatesByPath: templatesByPathArray,
      moduleByFile: moduleByFileArray,
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
    if (this.templatesByModule) this.templatesByModule.clear();
    if (this.templatesByPath) this.templatesByPath.clear();
    if (this.moduleByFile) this.moduleByFile.clear();
    if (this.fileHashes) this.fileHashes.clear();

    // Load templatesByModule
    if (cacheData.templatesByModule && Array.isArray(cacheData.templatesByModule)) {
      for (const [moduleName, templates] of cacheData.templatesByModule) {
        this.templatesByModule.set(moduleName, templates);
      }
    }

    // Load templatesByPath
    if (cacheData.templatesByPath && Array.isArray(cacheData.templatesByPath)) {
      for (const [path, template] of cacheData.templatesByPath) {
        this.templatesByPath.set(path, template);
      }
    }

    // Load moduleByFile
    if (cacheData.moduleByFile && Array.isArray(cacheData.moduleByFile)) {
      for (const [filePath, moduleName] of cacheData.moduleByFile) {
        this.moduleByFile.set(filePath, moduleName);
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

    const totalTemplates = this.templatesByModule
      ? Array.from(this.templatesByModule.values()).reduce((sum, temps) => sum + temps.length, 0)
      : 0;
    console.log(`[TemplatesRegistry] Loaded ${totalTemplates} templates from cache`);
  }
}
