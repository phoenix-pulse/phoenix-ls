import { spawn } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

// Concurrency limiter to prevent spawning too many Elixir processes simultaneously
// When parsing 30+ files in parallel, too many concurrent Elixir processes causes SIGTERM crashes
class ConcurrencyLimiter {
  private running = 0;
  private queue: Array<() => void> = [];

  constructor(private maxConcurrent: number = 5) {}

  async run<T>(fn: () => Promise<T>): Promise<T> {
    // Wait for available slot
    if (this.running >= this.maxConcurrent) {
      await new Promise<void>(resolve => this.queue.push(resolve));
    }

    this.running++;
    try {
      return await fn();
    } finally {
      this.running--;
      // Resume next queued task
      const next = this.queue.shift();
      if (next) next();
    }
  }
}

// Global limiter shared across all Elixir parsers
// Limit concurrent Elixir processes to prevent SIGTERM crashes
// Higher values = faster, but risk system resource exhaustion
const elixirConcurrencyLimiter = new ConcurrencyLimiter(10);

// Helper function to debug JSON parse failures
function logJsonParseError(parserName: string, filePath: string, stdout: string) {
  console.error(`[${parserName}] JSON parse failed for ${filePath}`);
  console.error(`[${parserName}] stdout length: ${stdout.length}`);
  console.error(`[${parserName}] stdout (first 500 chars): ${stdout.substring(0, 500)}`);
  console.error(`[${parserName}] stdout (last 100 chars): ${stdout.substring(Math.max(0, stdout.length - 100))}`);
  console.error(`[${parserName}] stdout (hex start): ${Buffer.from(stdout.substring(0, 100)).toString('hex')}`);
}

/**
 * Component metadata parsed from Elixir AST
 */
export interface ComponentMetadata {
  module: string | null;
  components: ComponentInfo[];
  file_path: string;
  pending_attrs: AttributeInfo[];
  pending_slots: SlotInfo[];
}

export interface ComponentInfo {
  name: string;
  line: number;
  attributes: AttributeInfo[];
  slots: SlotInfo[];
}

export interface AttributeInfo {
  name: string;
  type: string;
  line: number;
  required: boolean;
  default?: string | null;
  values?: string[] | null;
  doc?: string | null;
}

export interface SlotInfo {
  name: string;
  line: number;
  required: boolean;
  doc?: string | null;
  attributes: any[]; // For future slot attribute support
}

export interface ParserError {
  error: true;
  message: string;
  type: string;
}

/**
 * Result from Elixir parser - either metadata or error
 */
export type ParserResult = ComponentMetadata | ParserError;

/**
 * LRU Cache for parsed results (avoids re-parsing unchanged files)
 * Evicts least-recently-used entries when full.
 */
class ParserCache {
  private cache = new Map<string, { mtime: number; result: ComponentMetadata }>();
  private maxSize = 200;

  get(filePath: string): ComponentMetadata | null {
    try {
      const stats = fs.statSync(filePath);
      const cached = this.cache.get(filePath);

      if (cached && cached.mtime === stats.mtimeMs) {
        // Move to end (LRU: mark as recently used)
        this.cache.delete(filePath);
        this.cache.set(filePath, cached);
        return cached.result;
      }

      // File changed or not in cache
      return null;
    } catch (error) {
      // File doesn't exist or stat failed
      return null;
    }
  }

  set(filePath: string, result: ComponentMetadata): void {
    try {
      const stats = fs.statSync(filePath);

      // Evict least-recently-used entry if cache is full (LRU)
      if (this.cache.size >= this.maxSize) {
        const firstKey = this.cache.keys().next().value;
        this.cache.delete(firstKey);
      }

      this.cache.set(filePath, {
        mtime: stats.mtimeMs,
        result
      });
    } catch (error) {
      // Ignore cache errors
    }
  }

  invalidate(filePath: string): void {
    this.cache.delete(filePath);
  }

  clear(): void {
    this.cache.clear();
  }
}

const cache = new ParserCache();

/**
 * Checks if Elixir is available in the system
 */
export async function isElixirAvailable(): Promise<boolean> {
  return new Promise((resolve) => {
    const elixir = spawn('elixir', ['--version']);

    elixir.on('error', () => resolve(false));
    elixir.on('exit', (code) => resolve(code === 0));

    // Timeout after 2 seconds
    setTimeout(() => {
      elixir.kill();
      resolve(false);
    }, 2000);
  });
}

/**
 * Parse an Elixir file using the Elixir AST parser
 *
 * @param filePath - Absolute path to the .ex file
 * @param useCache - Whether to use cached results (default: true)
 * @returns Parsed component metadata or error
 */
export async function parseElixirFile(
  filePath: string,
  useCache: boolean = true
): Promise<ParserResult> {
  // Check cache first
  if (useCache) {
    const cached = cache.get(filePath);
    if (cached) {
      return cached;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/component-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/component-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000, // 10 second timeout
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as ParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as ComponentMetadata;
        if (useCache) {
          cache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirComponent', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate cache for a specific file (call when file changes)
 */
export function invalidateCache(filePath: string): void {
  cache.invalidate(filePath);
}

/**
 * Clear entire parser cache
 */
export function clearCache(): void {
  cache.clear();
}

/**
 * Type guard to check if result is an error
 */
export function isParserError(result: ParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if result is successful metadata
 */
export function isComponentMetadata(result: ParserResult): result is ComponentMetadata {
  return !isParserError(result);
}

// ============================================================================
// Schema Parser Types and Functions
// ============================================================================

export interface SchemaFieldInfo {
  name: string;
  type: string;
  elixir_type: string | null;
}

export interface SchemaAssociationInfo {
  field_name: string;
  target_module: string;
  type: string; // "belongs_to", "has_one", "has_many", "many_to_many", "embeds_one", "embeds_many"
}

export interface SchemaInfo {
  module_name: string;
  table_name: string | null;
  line: number;
  fields: SchemaFieldInfo[];
  associations: SchemaAssociationInfo[];
}

export interface SchemaMetadata {
  module: string | null;
  schemas: SchemaInfo[];
  file_path: string;
  aliases: Record<string, string>;
}

export type SchemaParserResult = SchemaMetadata | ParserError;

const schemaCache = new ParserCache();

/**
 * Parse an Elixir file for Ecto schemas using the Elixir AST parser
 */
export async function parseElixirSchemas(
  filePath: string,
  useCache: boolean = true
): Promise<SchemaParserResult> {
  // Check cache first
  if (useCache) {
    const cached = schemaCache.get(filePath);
    if (cached) {
      return cached as SchemaMetadata;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/schema-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/schema-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Schema parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as SchemaParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as SchemaMetadata;
        if (useCache) {
          schemaCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirSchema', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate schema cache for a specific file
 */
export function invalidateSchemaCache(filePath: string): void {
  schemaCache.invalidate(filePath);
}

/**
 * Clear entire schema parser cache
 */
export function clearSchemaCache(): void {
  schemaCache.clear();
}

/**
 * Type guard to check if schema result is an error
 */
export function isSchemaError(result: SchemaParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if schema result is successful metadata
 */
export function isSchemaMetadata(result: SchemaParserResult): result is SchemaMetadata {
  return !isSchemaError(result);
}

// ============================================================================
// Events Parser Types and Functions
// ============================================================================

export interface EventInfo {
  name: string;
  module_name: string;
  line: number;
  params: string;
  kind: 'handle_event' | 'handle_info';
  name_kind: 'string' | 'atom';
  doc: string | null;
}

export interface EventsMetadata {
  module: string | null;
  events: EventInfo[];
  file_path: string;
}

export type EventsParserResult = EventsMetadata | ParserError;

const eventsCache = new ParserCache();

/**
 * Parse an Elixir file for event handlers using the Elixir AST parser
 */
export async function parseElixirEvents(
  filePath: string,
  useCache: boolean = true
): Promise<EventsParserResult> {
  // Check cache first
  if (useCache) {
    const cached = eventsCache.get(filePath);
    if (cached) {
      return cached as EventsMetadata;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/events-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/events-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Events parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as EventsParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as EventsMetadata;
        if (useCache) {
          eventsCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirEvents', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate events cache for a specific file
 */
export function invalidateEventsCache(filePath: string): void {
  eventsCache.invalidate(filePath);
}

/**
 * Clear entire events parser cache
 */
export function clearEventsCache(): void {
  eventsCache.clear();
}

/**
 * Type guard to check if events result is an error
 */
export function isEventsError(result: EventsParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if events result is successful metadata
 */
export function isEventsMetadata(result: EventsParserResult): result is EventsMetadata {
  return !isEventsError(result);
}

// ============================================================================
// LiveView Parser Types and Functions
// ============================================================================

export interface LiveViewFunctionInfo {
  name: string;
  type: 'mount' | 'handle_event' | 'handle_info' | 'handle_params' | 'render';
  event_name?: string;
  line: number;
  module_name: string;
}

export interface LiveViewMetadata {
  module: string | null;
  functions: LiveViewFunctionInfo[];
  file_path: string;
}

export type LiveViewParserResult = LiveViewMetadata | ParserError;

const liveViewCache = new ParserCache();

/**
 * Parse an Elixir file for LiveView functions using the Elixir AST parser
 */
export async function parseElixirLiveView(
  filePath: string,
  useCache: boolean = true
): Promise<LiveViewParserResult> {
  // Check cache first
  if (useCache) {
    const cached = liveViewCache.get(filePath);
    if (cached) {
      return cached as LiveViewMetadata;
    }
  }

  // Get absolute path to parser script
  let parserScript = path.resolve(__dirname, '../elixir-parser/liveview-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/liveview-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `LiveView parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as LiveViewParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as LiveViewMetadata;
        if (useCache) {
          liveViewCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirLiveView', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate LiveView cache for a specific file
 */
export function invalidateLiveViewCache(filePath: string): void {
  liveViewCache.invalidate(filePath);
}

/**
 * Clear entire LiveView parser cache
 */
export function clearLiveViewCache(): void {
  liveViewCache.clear();
}

/**
 * Type guard to check if LiveView result is an error
 */
export function isLiveViewError(result: LiveViewParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if LiveView result is successful metadata
 */
export function isLiveViewMetadata(result: LiveViewParserResult): result is LiveViewMetadata {
  return !isLiveViewError(result);
}

// ============================================================================
// Router Parser Types and Functions
// ============================================================================

export interface RouteResourceOptions {
  only: string[] | null;
  except: string[] | null;
}

export interface RouteInfo {
  verb: string;
  path: string;
  controller?: string;
  action?: string;
  line: number;
  params: string[];
  alias: string | null;
  pipeline: string | null;
  scope_path: string;
  is_resource: boolean;
  live_module?: string;
  live_action?: string;
  forward_to?: string;
  resource_options?: RouteResourceOptions;
}

export interface RouterMetadata {
  routes: RouteInfo[];
  file_path: string;
}

export type RouterParserResult = RouterMetadata | ParserError;

const routerCache = new ParserCache();

/**
 * Parse an Elixir file for Phoenix routes using the Elixir AST parser
 */
export async function parseElixirRouter(
  filePath: string,
  useCache: boolean = true
): Promise<RouterParserResult> {
  // Check cache first
  if (useCache) {
    const cached = routerCache.get(filePath);
    if (cached) {
      return cached as RouterMetadata;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/router-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/router-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Router parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as RouterParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as RouterMetadata;
        if (useCache) {
          routerCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirRouter', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate router cache for a specific file
 */
export function invalidateRouterCache(filePath: string): void {
  routerCache.invalidate(filePath);
}

/**
 * Clear entire router parser cache
 */
export function clearRouterCache(): void {
  routerCache.clear();
}

/**
 * Type guard to check if router result is an error
 */
export function isRouterError(result: RouterParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if router result is successful metadata
 */
export function isRouterMetadata(result: RouterParserResult): result is RouterMetadata {
  return !isRouterError(result);
}

// ============================================================================
// Controller Parser Types and Functions
// ============================================================================

export interface ControllerAssignInfo {
  key: string;
  value: string;
}

export interface ControllerRenderInfo {
  action: string;
  line: number;
  view_module: string | null;
  template_name: string;
  template_format: string | null;
  assigns: ControllerAssignInfo[];
}

export interface ControllerMetadata {
  module: string | null;
  renders: ControllerRenderInfo[];
  file_path: string;
}

export type ControllerParserResult = ControllerMetadata | ParserError;

const controllerCache = new ParserCache();

/**
 * Parse an Elixir controller file for render() calls using the Elixir AST parser
 */
export async function parseElixirController(
  filePath: string,
  useCache: boolean = true
): Promise<ControllerParserResult> {
  // Check cache first
  if (useCache) {
    const cached = controllerCache.get(filePath);
    if (cached) {
      return cached as ControllerMetadata;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/controller-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/controller-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Controller parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as ControllerParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as ControllerMetadata;
        if (useCache) {
          controllerCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirController', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate controller cache for a specific file
 */
export function invalidateControllerCache(filePath: string): void {
  controllerCache.invalidate(filePath);
}

/**
 * Clear entire controller parser cache
 */
export function clearControllerCache(): void {
  controllerCache.clear();
}

/**
 * Type guard to check if controller result is an error
 */
export function isControllerError(result: ControllerParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if controller result is successful metadata
 */
export function isControllerMetadata(result: ControllerParserResult): result is ControllerMetadata {
  return !isControllerError(result);
}

// ============================================================================
// Template Parser Types and Functions
// ============================================================================

export interface FunctionTemplateInfo {
  name: string;
  line: number;
  format: string;
}

export interface TemplateMetadata {
  module: string | null;
  embed_templates: string[];
  module_type: 'view' | 'html' | null;
  function_templates: FunctionTemplateInfo[];
  file_path: string;
}

export type TemplateParserResult = TemplateMetadata | ParserError;

const templateCache = new ParserCache();

/**
 * Parse an Elixir template module file using the Elixir AST parser
 */
export async function parseElixirTemplate(
  filePath: string,
  useCache: boolean = true
): Promise<TemplateParserResult> {
  // Check cache first
  if (useCache) {
    const cached = templateCache.get(filePath);
    if (cached) {
      return cached as TemplateMetadata;
    }
  }

  // Get absolute path to parser script
  // In production (bundled), __dirname is lsp/dist/
  // In development, __dirname is lsp/dist/parsers/
  // Try both paths for compatibility
  let parserScript = path.resolve(__dirname, '../elixir-parser/template-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/template-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `Template parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000,
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `Elixir parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as TemplateParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as TemplateMetadata;
        if (useCache) {
          templateCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseElixirTemplate', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate template cache for a specific file
 */
export function invalidateTemplateCache(filePath: string): void {
  templateCache.invalidate(filePath);
}

/**
 * Clear entire template parser cache
 */
export function clearTemplateCache(): void {
  templateCache.clear();
}

/**
 * Type guard to check if template result is an error
 */
export function isTemplateError(result: TemplateParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if template result is successful metadata
 */
export function isTemplateMetadata(result: TemplateParserResult): result is TemplateMetadata {
  return !isTemplateError(result);
}

// ==================== HEEx Parser Integration ====================

/**
 * Component usage found in HEEx template
 */
export interface HEExComponentUsage {
  name: string;
  module_context: string | null;
  is_local: boolean;
  start_offset: number;
  end_offset: number;
  name_start: number;
  name_end: number;
  self_closing: boolean;
  attributes: any[];  // Attributes not yet parsed
  slots: HEExSlotUsage[];
  parent_component: string | null;
}

/**
 * Slot usage found in HEEx template
 */
export interface HEExSlotUsage {
  name: string;
  start_offset: number;
  end_offset: number;
  self_closing: boolean;
  attributes: any[];  // Attributes not yet parsed
}

/**
 * Metadata parsed from HEEx template
 */
export interface HEExMetadata {
  source: string;
  success: true;
  components: HEExComponentUsage[];
  error?: null;
}

/**
 * Result from HEEx parser - either metadata or error
 */
export type HEExParserResult = HEExMetadata | ParserError;

/**
 * Cache for HEEx parser results (file-based)
 */
const heexCache = new ParserCache() as any;  // Reuse ParserCache but for HEEx results

/**
 * Cache for HEEx content parsing (content-based, for ~H sigils in .ex files)
 * Uses content hash as key to avoid re-parsing identical content
 */
class HEExContentCache {
  private cache = new Map<string, HEExMetadata>();
  private maxSize = 100;  // Smaller than file cache since content can change frequently

  private hashContent(content: string): string {
    // Simple hash function (FNV-1a)
    let hash = 2166136261;
    for (let i = 0; i < content.length; i++) {
      hash ^= content.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  get(content: string): HEExMetadata | null {
    const hash = this.hashContent(content);
    const cached = this.cache.get(hash);
    if (cached) {
      // Move to end (LRU: mark as recently used)
      this.cache.delete(hash);
      this.cache.set(hash, cached);
      return cached;
    }
    return null;
  }

  set(content: string, result: HEExMetadata): void {
    const hash = this.hashContent(content);

    // Evict oldest entry if cache is full
    if (this.cache.size >= this.maxSize && !this.cache.has(hash)) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }

    this.cache.set(hash, result);
  }

  clear(): void {
    this.cache.clear();
  }
}

const heexContentCache = new HEExContentCache();

/**
 * Parse a HEEx template file using the Elixir HEEx parser
 *
 * @param filePath - Absolute path to the .heex file
 * @param useCache - Whether to use cached results (default: true)
 * @returns Parsed component usages or error
 */
export async function parseHEExFile(
  filePath: string,
  useCache: boolean = true
): Promise<HEExParserResult> {
  // Check cache first
  if (useCache) {
    const cached = heexCache.get(filePath);
    if (cached) {
      return cached;
    }
  }

  // Get absolute path to parser script
  // Try both production and development paths
  let parserScript = path.resolve(__dirname, '../elixir-parser/heex-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/heex-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `HEEx parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return {
      error: true,
      message: `File not found: ${filePath}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    const elixir = spawn('elixir', [parserScript, filePath], {
      timeout: 10000, // 10 second timeout
    });

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `HEEx parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as HEExParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as HEExMetadata;
        if (useCache) {
          heexCache.set(filePath, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseHEExFile', filePath, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Parse HEEx content from text (for .ex files with ~H sigils or in-memory content)
 *
 * @param content - HEEx template text content
 * @param source - Source identifier (e.g., file path or "stdin")
 * @returns Parsed component usages or error
 */
export async function parseHEExContent(
  content: string,
  source: string = 'stdin',
  useCache: boolean = true
): Promise<HEExParserResult> {
  // Check cache first
  if (useCache) {
    const cached = heexContentCache.get(content);
    if (cached) {
      console.log(`[parseHEExContent] ✅ Cache hit for ${source} (${content.length} chars)`);
      return cached;
    }
    console.log(`[parseHEExContent] ❌ Cache miss for ${source} (${content.length} chars)`);
  }

  // Get absolute path to parser script
  // Try both production and development paths
  let parserScript = path.resolve(__dirname, '../elixir-parser/heex-parser.exs');
  if (!fs.existsSync(parserScript)) {
    parserScript = path.resolve(__dirname, '../../elixir-parser/heex-parser.exs');
  }

  // Check if parser script exists
  if (!fs.existsSync(parserScript)) {
    return {
      error: true,
      message: `HEEx parser script not found: ${parserScript}`,
      type: 'FileNotFoundError'
    };
  }

  // Use concurrency limiter to prevent spawning too many Elixir processes
  return elixirConcurrencyLimiter.run(() => new Promise((resolve) => {
    let stdout = '';
    let stderr = '';

    // Use --stdin mode
    const elixir = spawn('elixir', [parserScript, '--stdin'], {
      timeout: 10000, // 10 second timeout
    });

    // Write content to stdin
    elixir.stdin.write(content);
    elixir.stdin.end();

    elixir.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    elixir.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    elixir.on('error', (error) => {
      resolve({
        error: true,
        message: `Failed to spawn Elixir: ${error.message}`,
        type: 'SpawnError'
      });
    });

    elixir.on('exit', (code) => {
      if (code !== 0) {
        resolve({
          error: true,
          message: `HEEx parser exited with code ${code}${stderr ? ': ' + stderr : ''}`,
          type: 'ExitError'
        });
        return;
      }

      try {
        const result = JSON.parse(stdout) as HEExParserResult;

        // Check if result is an error
        if ('error' in result && result.error) {
          resolve(result);
          return;
        }

        // Cache successful result
        const metadata = result as HEExMetadata;
        if (useCache) {
          heexContentCache.set(content, metadata);
        }

        resolve(metadata);
      } catch (error) {
        logJsonParseError('parseHEExContent', source, stdout);
        resolve({
          error: true,
          message: `Failed to parse JSON output: ${error instanceof Error ? error.message : String(error)}`,
          type: 'JSONParseError'
        });
      }
    });
  }));
}

/**
 * Invalidate HEEx cache for a specific file
 */
export function invalidateHEExCache(filePath: string): void {
  heexCache.invalidate(filePath);
}

/**
 * Clear entire HEEx parser cache
 */
export function clearHEExCache(): void {
  heexCache.clear();
}

/**
 * Type guard to check if HEEx result is an error
 */
export function isHEExError(result: HEExParserResult): result is ParserError {
  return 'error' in result && result.error === true;
}

/**
 * Type guard to check if HEEx result is successful metadata
 */
export function isHEExMetadata(result: HEExParserResult): result is HEExMetadata {
  return !isHEExError(result);
}
