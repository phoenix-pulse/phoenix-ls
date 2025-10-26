import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { TemplatesRegistry, TemplateInfo } from './templates-registry';
import { PerfTimer } from './utils/perf';
import { TypeInfo, inferTypeFromExpression, traceVariableType } from './utils/type-inference';
import {
  parseElixirController,
  isControllerMetadata,
  ControllerMetadata,
  isElixirAvailable
} from './parsers/elixir-ast-parser';

export interface AssignInfo {
  name: string;
  variableName: string; // The variable being assigned (might be same as name)
  typeInfo?: TypeInfo; // Inferred type information
}

export interface ControllerRenderInfo {
  controllerModule: string;
  controllerFile: string;
  action?: string;
  viewModule?: string;
  templateName: string;
  templateFormat?: string;
  templatePath?: string;
  assigns: string[]; // Keep for backward compatibility
  assignsWithTypes: AssignInfo[]; // New: includes type information
  line: number;
  actionBody?: string; // Store action body for type inference
}

export interface TemplateUsageSummary {
  templatePath: string;
  assignSources: Map<string, ControllerRenderInfo[]>;
  controllers: ControllerRenderInfo[];
}

export class ControllersRegistry {
  private templatesRegistry: TemplatesRegistry;
  private workspaceRoot = '';
  private fileHashes = new Map<string, string>();
  private rendersByFile = new Map<string, ControllerRenderInfo[]>();
  private templateSummaries = new Map<string, TemplateUsageSummary>();
  private useElixirParser: boolean = true;
  private elixirAvailable: boolean | null = null;

  constructor(templatesRegistry: TemplatesRegistry) {
    this.templatesRegistry = templatesRegistry;

    // Check environment variable to optionally disable Elixir parser
    const envVar = process.env.PHOENIX_PULSE_USE_REGEX_PARSER;
    if (envVar === 'true' || envVar === '1') {
      this.useElixirParser = false;
      console.log('[ControllersRegistry] Using regex parser (PHOENIX_PULSE_USE_REGEX_PARSER=true)');
    }
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
  }

  getTemplateSummary(templatePath: string): TemplateUsageSummary | null {
    return this.templateSummaries.get(templatePath) || null;
  }

  refreshTemplateSummaries() {
    this.rebuildTemplateSummaries();
  }

  getAssignsForTemplate(templatePath: string): string[] {
    const summary = this.templateSummaries.get(templatePath);
    if (!summary) {
      return [];
    }
    return Array.from(summary.assignSources.keys());
  }

  async updateFile(filePath: string, content: string) {
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previous = this.fileHashes.get(filePath);
    if (previous === hash) {
      return;
    }

    const timer = new PerfTimer('controllers.updateFile');
    const renders = await this.parseFileAsync(filePath, content);
    this.rendersByFile.set(filePath, renders);
    this.fileHashes.set(filePath, hash);
    this.rebuildTemplateSummaries();
    timer.stop({ file: path.relative(this.workspaceRoot || '', filePath), renders: renders.length });
  }

  removeFile(filePath: string) {
    this.rendersByFile.delete(filePath);
    this.fileHashes.delete(filePath);
    this.rebuildTemplateSummaries();
  }

  /**
   * Convert Elixir parser metadata to ControllerRenderInfo array
   */
  private convertElixirToRenderInfo(
    metadata: ControllerMetadata,
    filePath: string,
    content: string
  ): ControllerRenderInfo[] {
    const moduleName = metadata.module || this.extractModuleName(content);
    if (!moduleName) {
      return [];
    }

    return metadata.renders.map(render => {
      // Extract just the assign keys for backward compatibility
      const assignKeys = render.assigns.map(a => a.key);

      // Build AssignInfo array with type inference
      // Note: We don't have action body from Elixir parser yet, so type inference is limited
      const assignsWithTypes: AssignInfo[] = render.assigns.map(assign => ({
        name: assign.key,
        variableName: assign.value.replace(/^["']|["']$/g, ''), // Remove quotes if present
        typeInfo: undefined, // Could enhance parser to include action body for type inference
      }));

      return {
        controllerModule: moduleName,
        controllerFile: filePath,
        action: render.action,
        viewModule: render.view_module || undefined,
        templateName: render.template_name,
        templateFormat: render.template_format || undefined,
        assigns: assignKeys,
        assignsWithTypes,
        line: render.line,
      };
    });
  }

  /**
   * Parse controller file using Elixir AST parser
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<ControllerRenderInfo[] | null> {
    // Check if we should use Elixir parser
    if (!this.useElixirParser) {
      return null;
    }

    // Check Elixir availability (cached)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[ControllersRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[ControllersRegistry] Elixir not available - using regex parser');
      }
    }

    if (!this.elixirAvailable) {
      return null;
    }

    // Verbose log removed - happens before cache check, misleading

    try {
      const result = await parseElixirController(filePath);

      if (isControllerMetadata(result)) {
        return this.convertElixirToRenderInfo(result, filePath, content);
      } else {
        console.error(`[ControllersRegistry] Elixir parser error for ${filePath}:`, result.message);
        return null;
      }
    } catch (error) {
      console.error(`[ControllersRegistry] Elixir parser failed for ${filePath}:`, error);
      return null;
    }
  }

  /**
   * Parse controller file (tries Elixir parser first, falls back to regex)
   */
  private async parseFileAsync(filePath: string, content: string): Promise<ControllerRenderInfo[]> {
    // Try Elixir parser first
    const elixirResult = await this.parseFileWithElixir(filePath, content);
    if (elixirResult !== null) {
      return elixirResult;
    }

    // Fall back to regex parser
    return this.parseControllerFile(filePath, content);
  }

  async scanWorkspace(workspaceRoot: string) {
    this.workspaceRoot = workspaceRoot;

    // Collect all controller files first
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
          } else if (entry.isFile() && entry.name.endsWith('_controller.ex')) {
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

    const timer = new PerfTimer('controllers.scanWorkspace');
    scan(workspaceRoot);

    // Check Elixir availability once before parallel parsing
    // This prevents race condition where all parallel parses check simultaneously
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[ControllersRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[ControllersRegistry] Elixir not available - using regex parser');
      }
    }

    // Parse all files in parallel
    const parsePromises = filesToParse.map(async ({ path: filePath, content }) => {
      const hash = crypto.createHash('sha1').update(content).digest('hex');
      const renders = await this.parseFileAsync(filePath, content);

      // Update maps
      this.rendersByFile.set(filePath, renders);
      this.fileHashes.set(filePath, hash);
    });

    await Promise.all(parsePromises);

    // Rebuild summaries once after all parsing is done
    this.rebuildTemplateSummaries();

    timer.stop({ controllers: filesToParse.length, templates: this.templateSummaries.size });
  }

  private shouldSkipDir(name: string): boolean {
    return ['deps', '_build', 'node_modules', '.git', 'priv', 'assets'].includes(name);
  }

  private rebuildTemplateSummaries() {
    // Build new summaries FIRST (don't touch this.templateSummaries yet)
    // This prevents race conditions during the rebuild loop
    const newSummaries = new Map<string, TemplateUsageSummary>();

    for (const renderList of this.rendersByFile.values()) {
      for (const render of renderList) {
        const templatePath = this.resolveTemplatePath(render);
        if (!templatePath) {
          continue;
        }
        render.templatePath = templatePath;

        let summary = newSummaries.get(templatePath);
        if (!summary) {
          summary = {
            templatePath,
            assignSources: new Map<string, ControllerRenderInfo[]>(),
            controllers: [],
          };
          newSummaries.set(templatePath, summary);
        }

        for (const assign of render.assigns) {
          const sources = summary.assignSources.get(assign) ?? [];
          sources.push(render);
          summary.assignSources.set(assign, sources);
        }
        summary.controllers.push(render);
      }
    }

    // Atomic swap - race window reduced from 10-100ms to <1ms
    this.templateSummaries = newSummaries;
  }

  private parseControllerFile(filePath: string, content: string): ControllerRenderInfo[] {
    const moduleName = this.extractModuleName(content);
    if (!moduleName) {
      return [];
    }

    const lines = content.split('\n');
    const functionDefs = this.collectFunctionDefinitions(lines);
    const functionBodies = this.extractFunctionBodies(content, functionDefs);
    const renderMatches = this.collectRenderCalls(content);
    const renders: ControllerRenderInfo[] = [];

    for (const renderMatch of renderMatches) {
      const args = this.splitArguments(renderMatch.args);
      if (args.length < 2) {
        continue;
      }

      const lineNumber = this.calculateLineNumber(content, renderMatch.start);
      const action = this.resolveActionForLine(functionDefs, lineNumber);
      const actionBody = action ? functionBodies.get(action) : undefined;

      const parsed = this.parseRenderArguments(args, actionBody, moduleName);
      if (!parsed) {
        continue;
      }

      renders.push({
        controllerModule: moduleName,
        controllerFile: filePath,
        action,
        viewModule: parsed.viewModule,
        templateName: parsed.templateName,
        templateFormat: parsed.templateFormat,
        assigns: parsed.assigns,
        assignsWithTypes: parsed.assignsWithTypes,
        actionBody,
        line: lineNumber,
      });
    }

    return renders;
  }

  private extractModuleName(content: string): string | null {
    const match = content.match(/defmodule\s+([\w.]+)\s+do/);
    return match ? match[1] : null;
  }

  private collectFunctionDefinitions(lines: string[]): Array<{ line: number; name: string }> {
    const defs: Array<{ line: number; name: string }> = [];

    lines.forEach((line, index) => {
      const match = line.match(/^\s*defp?\s+([a-z_][a-z0-9_!?]*)/);
      if (match) {
        defs.push({ line: index + 1, name: match[1] });
      }
    });

    return defs;
  }

  private extractFunctionBodies(
    content: string,
    functionDefs: Array<{ line: number; name: string }>
  ): Map<string, string> {
    const bodies = new Map<string, string>();
    const lines = content.split('\n');

    for (let i = 0; i < functionDefs.length; i++) {
      const funcDef = functionDefs[i];
      const startLine = funcDef.line - 1; // Convert to 0-indexed

      // Find the end of this function (next function or end of file)
      const nextFuncLine = i < functionDefs.length - 1 ? functionDefs[i + 1].line - 1 : lines.length;

      // Extract function body (simple approach - get all lines until next def)
      const funcLines = lines.slice(startLine, nextFuncLine);

      // Find where the function body actually ends (look for matching 'end')
      let depth = 0;
      let endLine = funcLines.length;

      for (let j = 0; j < funcLines.length; j++) {
        const line = funcLines[j].trim();

        // Count 'do' keywords (start of blocks)
        // Only match block-style 'do', not inline 'do:' syntax
        // Also skip comments
        if (line.match(/\bdo\s*($|#)/) && !line.match(/^#/) && !line.match(/,\s*do:/)) {
          depth++;
        }

        // Count 'end' keywords (end of blocks)
        // Match 'end' at start of line or 'end ' or 'end,'
        if (line === 'end' || line.startsWith('end ') || line.startsWith('end,') || line.match(/^end\s*($|#)/)) {
          depth--;
          if (depth === 0) {
            endLine = j + 1;
            break;
          }
        }
      }

      const body = funcLines.slice(0, endLine).join('\n');
      bodies.set(funcDef.name, body);
    }

    return bodies;
  }

  private resolveActionForLine(
    defs: Array<{ line: number; name: string }>,
    lineNumber: number
  ): string | undefined {
    let action: string | undefined;
    for (const def of defs) {
      if (def.line <= lineNumber) {
        action = def.name;
      } else {
        break;
      }
    }
    return action;
  }

  private collectRenderCalls(content: string): Array<{ start: number; args: string }> {
    const matches: Array<{ start: number; args: string }> = [];
    let index = content.indexOf('render(');

    while (index !== -1) {
      const { args, endIndex } = this.extractParenthesesContent(content, index + 'render'.length);
      if (args != null) {
        matches.push({ start: index, args });
        index = content.indexOf('render(', endIndex);
      } else {
        index = content.indexOf('render(', index + 1);
      }
    }

    return matches;
  }

  private extractParenthesesContent(text: string, startIndex: number): { args: string | null; endIndex: number } {
    const openParenIndex = text.indexOf('(', startIndex);
    if (openParenIndex === -1) {
      return { args: null, endIndex: startIndex };
    }

    let depth = 0;
    let inSingle = false;
    let inDouble = false;
    let prev = '';

    for (let i = openParenIndex; i < text.length; i++) {
      const ch = text[i];

      if (inSingle) {
        if (ch === '\'' && prev !== '\\') {
          inSingle = false;
        }
      } else if (inDouble) {
        if (ch === '"' && prev !== '\\') {
          inDouble = false;
        }
      } else {
        if (ch === '\'') {
          inSingle = true;
        } else if (ch === '"') {
          inDouble = true;
        } else if (ch === '(') {
          depth++;
        } else if (ch === ')') {
          depth--;
          if (depth === 0) {
            const args = text.slice(openParenIndex + 1, i);
            return { args, endIndex: i + 1 };
          }
        }
      }

      prev = ch;
    }

    return { args: null, endIndex: startIndex };
  }

  private splitArguments(argString: string): string[] {
    const args: string[] = [];
    let current = '';
    let depth = 0;
    let inSingle = false;
    let inDouble = false;
    let prev = '';

    for (let i = 0; i < argString.length; i++) {
      const ch = argString[i];

      if (inSingle) {
        current += ch;
        if (ch === '\'' && prev !== '\\') {
          inSingle = false;
        }
      } else if (inDouble) {
        current += ch;
        if (ch === '"' && prev !== '\\') {
          inDouble = false;
        }
      } else {
        if (ch === '\'') {
          inSingle = true;
          current += ch;
        } else if (ch === '"') {
          inDouble = true;
          current += ch;
        } else if (ch === '(' || ch === '[' || ch === '{') {
          depth++;
          current += ch;
        } else if (ch === ')' || ch === ']' || ch === '}') {
          depth = Math.max(depth - 1, 0);
          current += ch;
        } else if (ch === ',' && depth === 0) {
          args.push(current.trim());
          current = '';
        } else {
          current += ch;
        }
      }
      prev = ch;
    }

    if (current.trim().length > 0) {
      args.push(current.trim());
    }

    return args;
  }

  private parseRenderArguments(
    args: string[],
    actionBody?: string,
    contextModule?: string
  ): {
    viewModule?: string;
    templateName: string;
    templateFormat?: string;
    assigns: string[];
    assignsWithTypes: AssignInfo[];
  } | null {
    if (args.length < 2) {
      return null;
    }

    let index = 1;
    let viewModule: string | undefined;
    let templateArg: string | undefined;

    const secondArg = args[index];
    if (this.looksLikeModule(secondArg)) {
      viewModule = secondArg;
      index++;
    }

    templateArg = args[index];
    if (!templateArg) {
      return null;
    }

    const { templateName, format } = this.normalizeTemplateArg(templateArg);
    const assignKeys = this.extractAssignKeys(args.slice(index + 1));

    // Infer types for each assign
    const assignsWithTypes: AssignInfo[] = assignKeys.map(assignKey => {
      const { key, value } = assignKey;

      // Try to infer type from the value expression or by tracing the variable
      let typeInfo: TypeInfo | undefined;

      if (value && actionBody) {
        // First try direct inference from the value expression
        typeInfo = inferTypeFromExpression(value, contextModule) || undefined;

        // If that fails, try tracing the variable in the action body
        if (!typeInfo) {
          typeInfo = traceVariableType(actionBody, value, contextModule) || undefined;
        }
      }

      return {
        name: key,
        variableName: value || key,
        typeInfo,
      };
    });

    return {
      viewModule,
      templateName,
      templateFormat: format,
      assigns: assignKeys.map(a => a.key), // Keep for backward compatibility
      assignsWithTypes,
    };
  }

  private looksLikeModule(value: string): boolean {
    return /^[A-Z][\w]*(?:\.[A-Z][\w]*)*$/.test(value);
  }

  private normalizeTemplateArg(arg: string): { templateName: string; format?: string } {
    let cleaned = arg.trim();
    let format: string | undefined;

    if (cleaned.startsWith(':')) {
      cleaned = cleaned.slice(1);
    } else if ((cleaned.startsWith('"') && cleaned.endsWith('"')) || (cleaned.startsWith('\'') && cleaned.endsWith('\''))) {
      cleaned = cleaned.slice(1, -1);
    }

    const parts = cleaned.split('/');
    const lastPart = parts[parts.length - 1];

    if (lastPart.includes('.')) {
      const segments = lastPart.split('.');
      if (segments.length > 1) {
        format = segments.pop();
        cleaned = segments.join('.');
      } else {
        cleaned = segments[0];
      }
    }

    return { templateName: cleaned, format };
  }

  private extractAssignKeys(assignArgs: string[]): Array<{ key: string; value: string }> {
    const assigns: Array<{ key: string; value: string }> = [];
    const seen = new Set<string>();

    for (const entry of assignArgs) {
      // Match patterns like: user: user, posts: posts, page_title: "Title"
      const match = entry.match(/^\s*:?([a-z_][a-z0-9_]*)\s*:\s*(.+)$/i);
      if (match) {
        const key = match[1];
        const value = match[2].trim();

        if (key && !seen.has(key)) {
          assigns.push({ key, value });
          seen.add(key);
        }
      }
    }

    return assigns;
  }

  private calculateLineNumber(text: string, index: number): number {
    let line = 1;
    for (let i = 0; i < index; i++) {
      if (text[i] === '\n') {
        line++;
      }
    }
    return line;
  }

  private resolveTemplatePath(render: ControllerRenderInfo): string | null {
    const templateCandidates: TemplateInfo[] = [];

    const candidateViewModules = this.collectCandidateViewModules(render);
    for (const viewModule of candidateViewModules) {
      const template = this.templatesRegistry.getTemplateByModule(
        viewModule,
        render.templateName,
        render.templateFormat
      );
      if (template) {
        templateCandidates.push(template);
      }
    }

    if (templateCandidates.length > 0) {
      return templateCandidates[0].filePath;
    }

    const guessed = this.guessTemplatePathFromController(render);
    if (guessed && fs.existsSync(guessed)) {
      return guessed;
    }

    return null;
  }

  private collectCandidateViewModules(render: ControllerRenderInfo): string[] {
    const candidates: string[] = [];
    if (render.viewModule) {
      candidates.push(render.viewModule);
    }

    if (render.controllerModule) {
      const parts = render.controllerModule.split('.');
      const moduleName = parts.pop() || '';
      const prefix = parts.join('.');
      const base = moduleName.replace(/Controller$/, '');
      if (base) {
        const htmlModule = `${prefix ? `${prefix}.` : ''}${base}HTML`;
        const viewModule = `${prefix ? `${prefix}.` : ''}${base}View`;
        if (!render.viewModule || render.viewModule !== htmlModule) {
          candidates.push(htmlModule);
        }
        if (!render.viewModule || render.viewModule !== viewModule) {
          candidates.push(viewModule);
        }
      }
    }

    return Array.from(new Set(candidates));
  }

  private guessTemplatePathFromController(render: ControllerRenderInfo): string | null {
    const controllerFile = render.controllerFile;
    const baseName = path.basename(controllerFile, path.extname(controllerFile)).replace(/_controller$/, '');
    if (!baseName) {
      return null;
    }

    const controllerDir = path.dirname(controllerFile);
    const templateName = render.templateName;
    const formats = render.templateFormat ? [render.templateFormat] : ['html'];
    const extensions = ['heex', 'leex', 'eex'];

    const pathsToTry: string[] = [];

    // Phoenix <= 1.6 style: lib/.../templates/<resource>/<template>.<format>.heex
    const templatesDir = path.join(path.dirname(controllerDir), 'templates', baseName);
    for (const format of formats) {
      for (const ext of extensions) {
        pathsToTry.push(path.join(templatesDir, `${templateName}.${format}.${ext}`));
      }
    }

    // Phoenix 1.7+ embed style: lib/.../controllers/<resource>_html/<template>.<format>.heex
    const embedDir = path.join(controllerDir, `${baseName}_html`);
    for (const format of formats) {
      for (const ext of extensions) {
        pathsToTry.push(path.join(embedDir, `${templateName}.${format}.${ext}`));
      }
    }

    for (const candidate of pathsToTry) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const rendersByFileArray: Array<[string, ControllerRenderInfo[]]> = this.rendersByFile ? Array.from(this.rendersByFile.entries()) : [];
    const templateSummariesArray: Array<[string, TemplateUsageSummary]> = this.templateSummaries ? Array.from(this.templateSummaries.entries()) : [];
    const fileHashesObj: Record<string, string> = {};

    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        fileHashesObj[filePath] = hash;
      }
    }

    return {
      rendersByFile: rendersByFileArray,
      templateSummaries: templateSummariesArray,
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
    if (this.rendersByFile) this.rendersByFile.clear();
    if (this.templateSummaries) this.templateSummaries.clear();
    if (this.fileHashes) this.fileHashes.clear();

    // Load rendersByFile
    if (cacheData.rendersByFile && Array.isArray(cacheData.rendersByFile)) {
      for (const [filePath, renders] of cacheData.rendersByFile) {
        this.rendersByFile.set(filePath, renders);
      }
    }

    // Load templateSummaries
    if (cacheData.templateSummaries && Array.isArray(cacheData.templateSummaries)) {
      for (const [path, summary] of cacheData.templateSummaries) {
        this.templateSummaries.set(path, summary);
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

    const totalRenders = this.rendersByFile
      ? Array.from(this.rendersByFile.values()).reduce((sum, renders) => sum + renders.length, 0)
      : 0;
    console.log(`[ControllersRegistry] Loaded ${this.rendersByFile?.size || 0} controller files with ${totalRenders} render() calls from cache`);
  }
}
