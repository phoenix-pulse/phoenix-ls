import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { PerfTimer, time } from './utils/perf';
import {
  parseElixirEvents,
  isEventsError,
  isEventsMetadata,
  isElixirAvailable,
  type EventsMetadata,
  type EventInfo,
} from './parsers/elixir-ast-parser';

export type PhoenixEventNameKind = 'string' | 'atom';

export interface PhoenixEvent {
  name: string;
  filePath: string;
  moduleName: string;
  line: number;
  params: string; // The params pattern, e.g., "params" or "%{\"id\" => id}"
  kind: 'handle_event' | 'handle_info';
  doc?: string;
  clause?: string;
  nameKind: PhoenixEventNameKind;
}

export class EventsRegistry {
  private events: Map<string, PhoenixEvent[]> = new Map(); // normalized filePath -> events
  private workspaceRoot: string = '';
  private fileHashes: Map<string, string> = new Map();
  private templateEventUsage: Map<string, Map<string, Set<string>>> = new Map(); // moduleFile -> (templatePath -> events)
  private useElixirParser: boolean = true;
  private elixirAvailable: boolean | null = null;

  constructor() {
    // Allow disabling Elixir parser via environment variable (useful for testing/debugging)
    const envVar = process.env.PHOENIX_PULSE_USE_REGEX_PARSER;
    if (envVar === 'true' || envVar === '1') {
      this.useElixirParser = false;
      console.log('[EventsRegistry] Elixir parser disabled via PHOENIX_PULSE_USE_REGEX_PARSER');
    }
  }

  private normalizePath(filePath: string): string {
    return path.normalize(filePath);
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
  }

  /**
   * Parse a single Elixir file and extract handle_event definitions
   */
  parseFile(filePath: string, content: string): PhoenixEvent[] {
    const normalizedPath = this.normalizePath(filePath);
    const timer = new PerfTimer('events.parseFile');
    const events: PhoenixEvent[] = [];
    const lines = content.split('\n');

    let moduleName = '';
    for (const line of lines) {
      const moduleMatch = /defmodule\s+([\w.]+)\s+do/.exec(line);
      if (moduleMatch) {
        moduleName = moduleMatch[1];
        break;
      }
    }

    let pendingDoc: string | null = null;
    let collectingDoc = false;
    let docBuffer: string[] = [];

    lines.forEach((line, index) => {
      // Match patterns like:
      // def handle_event("event_name", params, socket)
      // defp handle_event("event_name", params, socket)  <- private
      // def handle_event("event_name", %{"key" => value}, socket)
      // @impl true + handle_event

      const trimmedLine = line.trim();

      if (collectingDoc) {
        const endIdx = line.indexOf('"""');
        if (endIdx !== -1) {
          const contentPart = line.slice(0, endIdx);
          if (contentPart.trim().length > 0) {
            docBuffer.push(contentPart.trim());
          }
          pendingDoc = docBuffer.join('\n').trim();
          collectingDoc = false;
          docBuffer = [];
        } else if (trimmedLine.length > 0) {
          docBuffer.push(trimmedLine);
        }
      } else if (trimmedLine.startsWith('@doc')) {
        const tripleMatch = /@doc\s+"""/.exec(trimmedLine);
        if (tripleMatch) {
          const startIdx = line.indexOf('"""');
          const after = line.slice(startIdx + 3);
          const endIdx = after.indexOf('"""');
          if (endIdx !== -1) {
            const contentPart = after.slice(0, endIdx).trim();
            pendingDoc = contentPart.length > 0 ? contentPart : null;
          } else {
            collectingDoc = true;
            docBuffer = [];
            if (after.trim().length > 0) {
              docBuffer.push(after.trim());
            }
          }
        } else {
          if (/@doc\s+(false|nil)/.test(trimmedLine)) {
            pendingDoc = null;
          } else {
            const docMatch = /@doc\s+["']([^"']+)["']/.exec(trimmedLine);
            pendingDoc = docMatch ? docMatch[1] : null;
          }
        }
      }

      // Pattern 1: Standard handle_event with string literal
      const standardPattern = /(?:def|defp)\s+handle_event\s*\(\s*"([^"]+)"\s*,\s*([^,]+)\s*,/g;
      let match;

      standardPattern.lastIndex = 0;
      while ((match = standardPattern.exec(line)) !== null) {
        const eventName = match[1];
        const params = match[2].trim();

        events.push({
          name: eventName,
          filePath: normalizedPath,
          moduleName,
          line: index + 1,
          params,
          kind: 'handle_event',
          doc: pendingDoc || undefined,
          clause: trimmedLine,
          nameKind: 'string',
        });
        pendingDoc = null;
      }

      // Pattern 2: handle_event with single quotes (rare but valid)
      const singleQuotePattern = /(?:def|defp)\s+handle_event\s*\(\s*'([^']+)'\s*,\s*([^,]+)\s*,/g;
      singleQuotePattern.lastIndex = 0;
      while ((match = singleQuotePattern.exec(line)) !== null) {
        const eventName = match[1];
        const params = match[2].trim();

        events.push({
          name: eventName,
          filePath: normalizedPath,
          moduleName,
          line: index + 1,
          params,
          kind: 'handle_event',
          doc: pendingDoc || undefined,
          clause: trimmedLine,
          nameKind: 'string',
        });
        pendingDoc = null;
      }

      // Pattern 3: Atom-based event names (less common)
      // def handle_event(:event_name, params, socket)
      const atomPattern = /(?:def|defp)\s+handle_event\s*\(\s*:([a-z_][a-z0-9_]*)\s*,\s*([^,]+)\s*,/g;
      atomPattern.lastIndex = 0;
      while ((match = atomPattern.exec(line)) !== null) {
        const eventName = match[1];
        const params = match[2].trim();

        events.push({
          name: eventName,
          filePath: normalizedPath,
          moduleName,
          line: index + 1,
          params,
          kind: 'handle_event',
          doc: pendingDoc || undefined,
          clause: trimmedLine,
          nameKind: 'atom',
        });
        pendingDoc = null;
      }

      const handleInfoAtomPattern = /(?:def|defp)\s+handle_info\s*\(\s*:([a-z_][a-z0-9_]*)\s*,/g;
      handleInfoAtomPattern.lastIndex = 0;
      while ((match = handleInfoAtomPattern.exec(line)) !== null) {
        const eventName = match[1];
        events.push({
          name: eventName,
          filePath: normalizedPath,
          moduleName,
          line: index + 1,
          params: ':atom',
          kind: 'handle_info',
          doc: pendingDoc || undefined,
          clause: trimmedLine,
          nameKind: 'atom',
        });
        pendingDoc = null;
      }

      const handleInfoStringPattern = /(?:def|defp)\s+handle_info\s*\(\s*"([^"\\]+)"\s*,/g;
      handleInfoStringPattern.lastIndex = 0;
      while ((match = handleInfoStringPattern.exec(line)) !== null) {
        const eventName = match[1];
        events.push({
          name: eventName,
          filePath: normalizedPath,
          moduleName,
          line: index + 1,
          params: '"string"',
          kind: 'handle_info',
          doc: pendingDoc || undefined,
          clause: trimmedLine,
          nameKind: 'string',
        });
        pendingDoc = null;
      }
    });

    timer.stop({ file: path.relative(this.workspaceRoot || '', normalizedPath), count: events.length });
    return events;
  }

  /**
   * Convert Elixir parser metadata to PhoenixEvent format
   */
  private convertElixirToPhoenixEvents(
    metadata: EventsMetadata,
    filePath: string
  ): PhoenixEvent[] {
    const normalizedPath = this.normalizePath(filePath);

    return metadata.events.map(event => ({
      name: event.name,
      filePath: normalizedPath,
      moduleName: event.module_name,
      line: event.line,
      params: event.params,
      kind: event.kind,
      doc: event.doc || undefined,
      nameKind: event.name_kind,
      clause: undefined, // Elixir parser doesn't extract full clause (not needed for completions)
    }));
  }

  /**
   * Parse file using Elixir AST parser (async)
   * Returns null if Elixir unavailable or parsing fails
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<PhoenixEvent[] | null> {
    // Check if we should use Elixir parser
    if (!this.useElixirParser) {
      return null;
    }

    // Check Elixir availability (cached after first check)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (!this.elixirAvailable) {
        console.log('[EventsRegistry] Elixir not available, falling back to regex parser');
      }
    }

    if (!this.elixirAvailable) {
      return null;
    }

    const normalizedPath = this.normalizePath(filePath);
    const timer = new PerfTimer('events.parseFileWithElixir');

    try {
      const result = await parseElixirEvents(normalizedPath, false);

      if (isEventsError(result)) {
        console.log(
          `[EventsRegistry] Elixir parser failed for ${path.relative(this.workspaceRoot || '', normalizedPath)}: ${result.message}`
        );
        return null;
      }

      if (isEventsMetadata(result)) {
        const events = this.convertElixirToPhoenixEvents(result, normalizedPath);
        timer.stop({
          file: path.relative(this.workspaceRoot || '', normalizedPath),
          count: events.length,
          parser: 'elixir',
        });
        return events;
      }

      return null;
    } catch (error) {
      console.log(
        `[EventsRegistry] Elixir parser exception for ${path.relative(this.workspaceRoot || '', normalizedPath)}: ${error instanceof Error ? error.message : String(error)}`
      );
      return null;
    }
  }

  /**
   * Parse file with Elixir parser first, fallback to regex
   * This is the async version used during workspace scanning
   */
  async parseFileAsync(filePath: string, content: string): Promise<PhoenixEvent[]> {
    // Try Elixir parser first
    const elixirEvents = await this.parseFileWithElixir(filePath, content);
    if (elixirEvents !== null) {
      return elixirEvents;
    }

    // Fallback to regex parser
    return this.parseFile(filePath, content);
  }

  /**
   * Update events for a specific file
   */
  async updateFile(filePath: string, content: string) {
    const normalizedPath = this.normalizePath(filePath);
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previousHash = this.fileHashes.get(normalizedPath);

    if (previousHash === hash && this.events.has(normalizedPath)) {
      return;
    }

    const timer = new PerfTimer('events.updateFile');
    const events = await this.parseFileAsync(normalizedPath, content);

    // Always update the registry, even if parsing returned 0 events
    // This prevents registry corruption due to transient parsing failures
    // (consistent with ComponentsRegistry pattern)
    this.events.set(normalizedPath, events);
    this.fileHashes.set(normalizedPath, hash);

    timer.stop({ file: path.relative(this.workspaceRoot || '', normalizedPath), events: events.length });
  }

  /**
   * Remove a file from the registry
   */
  removeFile(filePath: string) {
    const normalizedPath = this.normalizePath(filePath);
    this.events.delete(normalizedPath);
    this.fileHashes.delete(normalizedPath);
    this.templateEventUsage.delete(normalizedPath);
  }

  /**
   * Get all events from all files
   */
  getAllEvents(): PhoenixEvent[] {
    const allEvents: PhoenixEvent[] = [];
    this.events.forEach((events) => {
      allEvents.push(...events);
    });
    return allEvents;
  }

  /**
   * Check if an event exists in the registry
   */
  eventExists(eventName: string): boolean {
    for (const events of this.events.values()) {
      if (events.some(event => event.kind === 'handle_event' && event.name === eventName)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Get events from a specific file
   */
  getEventsFromFile(filePath: string): PhoenixEvent[] {
    const normalizedPath = this.normalizePath(filePath);
    return this.events.get(normalizedPath) || [];
  }

  /**
   * Try to find the LiveView module for a template file
   * For example: app_web/live/user_live/index.html.heex -> app_web/live/user_live/index.ex
   */
  findLiveViewModule(templatePath: string): string | null {
    const normalizedTemplate = this.normalizePath(templatePath);

    if (normalizedTemplate.endsWith('.ex') || normalizedTemplate.endsWith('.exs')) {
      return normalizedTemplate;
    }

    // Remove .html.heex or .heex extension
    let basePath = templatePath.replace(/\.html\.heex$/, '').replace(/\.heex$/, '');

    // Try with .ex extension
    const exPath = basePath + '.ex';
    if (fs.existsSync(exPath)) {
      return this.normalizePath(exPath);
    }

    // Try removing _live suffix and adding .ex
    basePath = basePath.replace(/_live$/, '_live');
    const exPath2 = basePath + '.ex';
    if (fs.existsSync(exPath2)) {
      return this.normalizePath(exPath2);
    }

    return null;
  }

  /**
   * Get events relevant to a specific template
   * Prioritizes events from the same module
   */
  getEventsForTemplate(templatePath: string): { primary: PhoenixEvent[]; secondary: PhoenixEvent[] } {
    const moduleFile = this.findLiveViewModule(templatePath);
    const primary: PhoenixEvent[] = [];
    const secondary: PhoenixEvent[] = [];

    this.events.forEach((events, filePath) => {
      const filtered = events.filter(event => event.kind === 'handle_event');
      if (filtered.length === 0) {
        return;
      }
      if (moduleFile && filePath === moduleFile) {
        primary.push(...filtered);
      } else {
        secondary.push(...filtered);
      }
    });

    return { primary, secondary };
  }

  updateTemplateEventUsage(templatePath: string, modulePath: string, events: Set<string>) {
    const normalizedModule = this.normalizePath(modulePath);
    const normalizedTemplate = this.normalizePath(templatePath);
    let byTemplate = this.templateEventUsage.get(normalizedModule);
    if (!byTemplate) {
      byTemplate = new Map();
      this.templateEventUsage.set(normalizedModule, byTemplate);
    }
    byTemplate.set(normalizedTemplate, new Set(events));
  }

  removeTemplateEventUsage(templatePath: string) {
    const normalizedTemplate = this.normalizePath(templatePath);
    for (const [modulePath, templateMap] of this.templateEventUsage.entries()) {
      if (templateMap.delete(normalizedTemplate) && templateMap.size === 0) {
        this.templateEventUsage.delete(modulePath);
      }
    }
  }

  getAggregatedTemplateEvents(modulePath: string): Set<string> {
    const normalizedModule = this.normalizePath(modulePath);
    const aggregated = new Set<string>();
    const usageMap = this.templateEventUsage.get(normalizedModule);
    if (!usageMap) {
      return aggregated;
    }
    for (const events of usageMap.values()) {
      for (const eventName of events) {
        aggregated.add(eventName);
      }
    }
    return aggregated;
  }

  getUnusedEventsForModule(modulePath: string): PhoenixEvent[] {
    const normalizedModule = this.normalizePath(modulePath);
    const events = this.events.get(normalizedModule) ?? [];
    const used = this.getAggregatedTemplateEvents(normalizedModule);
    return events.filter(event =>
      event.kind === 'handle_event' &&
      event.nameKind === 'string' &&
      !used.has(event.name)
    );
  }

  getHandleInfoEventsFromFile(filePath: string): PhoenixEvent[] {
    const events = this.events.get(filePath) || [];
    return events.filter(event => event.kind === 'handle_info');
  }

  /**
   * Scan workspace for .ex files and parse them
   */
  async scanWorkspace(workspaceRoot: string): Promise<void> {
    this.workspaceRoot = workspaceRoot;

    // Collect all .ex/.exs files first
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
            // Skip files that will never have events (performance optimization)
            // Events exist in:
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
    // This prevents race condition where all parallel parses check simultaneously
    if (this.useElixirParser && this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (this.elixirAvailable) {
        console.log('[EventsRegistry] Elixir detected - using AST parser');
      } else {
        console.log('[EventsRegistry] Elixir not available, falling back to regex parser');
      }
    }

    // Parse all files asynchronously
    const parseTimer = new PerfTimer('events.scanWorkspace');
    const parsePromises = filesToParse.map(async ({ path: filePath, content }) => {
      try {
        const events = await this.parseFileAsync(filePath, content);
        const normalizedPath = this.normalizePath(filePath);
        const hash = crypto.createHash('sha1').update(content).digest('hex');

        this.events.set(normalizedPath, events);
        this.fileHashes.set(normalizedPath, hash);
      } catch (err) {
        // Ignore parse errors for individual files
        console.log(`[EventsRegistry] Failed to parse ${filePath}: ${err instanceof Error ? err.message : String(err)}`);
      }
    });

    await Promise.all(parsePromises);

    const totalEvents = Array.from(this.events.values()).reduce((sum, events) => sum + events.length, 0);
    parseTimer.stop({
      root: workspaceRoot,
      files: filesToParse.length,
      events: totalEvents,
    });
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const eventsArray: Array<[string, PhoenixEvent[]]> = this.events ? Array.from(this.events.entries()) : [];
    const fileHashesObj: Record<string, string> = {};

    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        fileHashesObj[filePath] = hash;
      }
    }

    return {
      events: eventsArray,
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
    if (this.events) this.events.clear();
    if (this.fileHashes) this.fileHashes.clear();

    // Load events
    if (cacheData.events && Array.isArray(cacheData.events)) {
      for (const [filePath, events] of cacheData.events) {
        this.events.set(filePath, events);
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

    const totalEvents = Array.from(this.events.values()).reduce((sum, events) => sum + events.length, 0);
    console.log(`[EventsRegistry] Loaded ${totalEvents} events from cache`);
  }
}
