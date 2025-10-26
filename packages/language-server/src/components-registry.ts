import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { PerfTimer, time } from './utils/perf';
import {
  parseElixirFile,
  isParserError,
  isElixirAvailable,
  type ComponentMetadata,
  type ComponentInfo as ElixirComponentInfo,
  type AttributeInfo as ElixirAttributeInfo,
  type SlotInfo as ElixirSlotInfo,
} from './parsers/elixir-ast-parser';

const debugFlagString = process.env.PHOENIX_PULSE_DEBUG ?? '';
const DEBUG_FLAGS = new Set(
  debugFlagString
    .split(',')
    .map(flag => flag.trim().toLowerCase())
    .filter(Boolean)
);

function debugLog(flag: string, message: string) {
  if (DEBUG_FLAGS.has('all') || DEBUG_FLAGS.has(flag)) {
    console.log(`[PhoenixPulse:${flag}] ${message}`);
  }
}

const BUILTIN_RESOURCES_DIR = path.join(__dirname, '..', 'resources');
const BUILTIN_PHOENIX_COMPONENT_PATH = path.join(
  BUILTIN_RESOURCES_DIR,
  'phoenix_component_builtins.ex'
);
const NORMALIZED_BUILTIN_PHOENIX_COMPONENT_PATH = path.normalize(
  path.resolve(BUILTIN_PHOENIX_COMPONENT_PATH)
);
const BUILTIN_PHOENIX_COMPONENT_LINES = computeBuiltinLineNumbers(
  BUILTIN_PHOENIX_COMPONENT_PATH
);
const BUILTIN_RESOURCE_PATHS = new Set<string>([
  NORMALIZED_BUILTIN_PHOENIX_COMPONENT_PATH,
]);

function computeBuiltinLineNumbers(filePath: string): Map<string, number> {
  const lineNumbers = new Map<string, number>();

  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const lines = content.split('\n');

    lines.forEach((line, index) => {
      const match = line.match(/^\s*def\s+([a-z_][a-z0-9_]*)\b/);
      if (match) {
        lineNumbers.set(match[1], index + 1);
      }
    });
  } catch (error) {
    debugLog(
      'definition',
      `[components] Failed to load builtin component stubs from ${filePath}: ${error}`
    );
  }

  return lineNumbers;
}

function getBuiltinComponentLine(name: string): number {
  return BUILTIN_PHOENIX_COMPONENT_LINES.get(name) ?? 1;
}

function isBuiltinResourcePath(filePath: string): boolean {
  const normalized = path.normalize(path.resolve(filePath));
  return BUILTIN_RESOURCE_PATHS.has(normalized);
}

function computeHash(content: string): string {
  return crypto.createHash('sha1').update(content).digest('hex');
}

/**
 * Represents a component attribute declared with attr/3
 */
export interface ComponentAttribute {
  name: string;
  type: string; // :string, :atom, :boolean, :integer, etc.
  required: boolean;
  default?: string;
  values?: string[]; // For enum types (e.g., values: [:sm, :md, :lg])
  doc?: string;
  rawType?: string; // Original type expression (e.g., :string, MyApp.User)
}

/**
 * Represents a component slot declared with slot/3
 */
export interface ComponentSlot {
  name: string;
  required: boolean;
  doc?: string;
  attributes: ComponentAttribute[]; // Slots can have their own attributes
}

/**
 * Represents a Phoenix function component
 */
export interface PhoenixComponent {
  name: string; // Function name (e.g., "button")
  moduleName: string; // Full module name (e.g., "AppWeb.CoreComponents")
  filePath: string;
  line: number;
  attributes: ComponentAttribute[];
  slots: ComponentSlot[];
  doc?: string; // Component documentation
}

/**
 * Represents import and alias information from an Elixir file
 */
export interface ImportInfo {
  importedModules: string[];  // e.g., ["MyApp.CustomComponents"]
  aliasedModules: Map<string, string>;  // Short -> Full (e.g., "CustomComponents" -> "MyApp.CustomComponents")
}

/**
 * Format attribute type for display purposes (preserves original expression when available)
 */
export function getAttributeTypeDisplay(attribute: ComponentAttribute): string {
  if (attribute.rawType && attribute.rawType.trim().length > 0) {
    return attribute.rawType.trim();
  }

  const type = attribute.type || '';

  if (
    type.startsWith('{') ||
    type.startsWith('[') ||
    type.startsWith('(') ||
    type.startsWith('%') ||
    /^[A-Z]/.test(type) ||
    type.includes('.')
  ) {
    return type;
  }

  return `:${type}`;
}

export class ComponentsRegistry {
  private components: Map<string, PhoenixComponent[]> = new Map(); // filePath -> components
  private workspaceRoot: string = '';
  private fileHashes: Map<string, string> = new Map();
  private builtinsRegistered = false;
  private useElixirParser: boolean = true; // Feature flag: use Elixir AST parser
  private elixirAvailable: boolean | null = null; // Cache Elixir availability check

  constructor() {
    this.ensureBuiltinComponents();
    // Check environment variable to disable Elixir parser
    if (process.env.PHOENIX_PULSE_USE_REGEX_PARSER === 'true') {
      this.useElixirParser = false;
      debugLog('parser', '[ComponentsRegistry] Elixir parser disabled via env var');
    }
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = this.normalizePath(root);
  }

  getWorkspaceRoot(): string {
    return this.workspaceRoot;
  }

  private normalizePath(filePath: string): string {
    return path.normalize(path.resolve(filePath));
  }

  /**
   * Convert Elixir AST parser output to PhoenixComponent format
   */
  private convertElixirToPhoenixComponents(
    metadata: ComponentMetadata,
    filePath: string
  ): PhoenixComponent[] {
    const components: PhoenixComponent[] = [];

    for (const elixirComp of metadata.components) {
      const attributes: ComponentAttribute[] = elixirComp.attributes.map(
        (attr) => ({
          name: attr.name,
          type: attr.type,
          required: attr.required,
          default: attr.default || undefined,
          values: attr.values || undefined,
          doc: attr.doc || undefined,
          rawType: attr.type, // Store original type
        })
      );

      const slots: ComponentSlot[] = elixirComp.slots.map((slot) => ({
        name: slot.name,
        required: slot.required,
        doc: slot.doc || undefined,
        attributes: slot.attributes || [],
      }));

      components.push({
        name: elixirComp.name,
        moduleName: metadata.module || '',
        filePath: filePath,
        line: elixirComp.line,
        attributes,
        slots,
        doc: undefined, // Elixir parser doesn't capture @doc yet
      });
    }

    return components;
  }

  /**
   * Parse a single Elixir file using the Elixir AST parser (with fallback to regex)
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<PhoenixComponent[] | null> {
    // Check if Elixir is available (cache result)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (!this.elixirAvailable) {
        console.log('[Phoenix Pulse] Elixir not available - using regex parser only');
        this.useElixirParser = false; // Disable for future calls
      } else {
        console.log('[Phoenix Pulse] Elixir detected - using AST parser');
      }
    }

    if (!this.useElixirParser || !this.elixirAvailable) {
      return null; // Signal to use regex fallback
    }

    try {
      const result = await parseElixirFile(filePath, true);

      if (isParserError(result)) {
        debugLog('parser', `[ComponentsRegistry] Elixir parser error for ${filePath}: ${result.message}`);
        return null; // Fall back to regex
      }

      const metadata = result as ComponentMetadata;
      const components = this.convertElixirToPhoenixComponents(metadata, filePath);

      debugLog('parser', `[ComponentsRegistry] Elixir parser found ${components.length} components in ${filePath}`);

      return components;
    } catch (error) {
      debugLog('parser', `[ComponentsRegistry] Elixir parser exception for ${filePath}: ${error}`);
      return null; // Fall back to regex
    }
  }

  /**
   * Parse a single Elixir file asynchronously (tries Elixir AST parser first)
   * Used by scanWorkspace for initial scanning
   */
  async parseFileAsync(filePath: string, content: string): Promise<PhoenixComponent[]> {
    // Try Elixir parser first
    const elixirComponents = await this.parseFileWithElixir(filePath, content);

    if (elixirComponents !== null) {
      return elixirComponents;
    }

    // Fall back to regex parser
    debugLog('parser', `[ComponentsRegistry] Using regex parser for ${filePath}`);
    return this.parseFile(filePath, content);
  }

  /**
   * Parse a single Elixir file and extract component definitions (synchronous, regex-based)
   * This is the fallback parser and used for immediate parsing needs
   */
  parseFile(filePath: string, content: string): PhoenixComponent[] {
    if (!content) {
      return [];
    }

    const timer = new PerfTimer(`components.parseFile`);
    const components: PhoenixComponent[] = [];
    const lines = content.split('\n');

    // First, extract the module name
    let moduleName = '';
    for (const line of lines) {
      const moduleMatch = /defmodule\s+([\w.]+)\s+do/.exec(line);
      if (moduleMatch) {
        moduleName = moduleMatch[1];
        break;
      }
    }

    // If no module found, skip this file
    if (!moduleName) {
      return components;
    }

    // Track current component being parsed
    let currentComponent: PhoenixComponent | null = null;
    let currentDoc: string | null = null;

    // Track attributes and slots WITH LINE NUMBERS for proximity-based assignment
    interface PendingAttr {
      attr: ComponentAttribute;
      line: number;
    }
    interface PendingSlot {
      slot: ComponentSlot;
      line: number;
    }

    let pendingAttributesWithLines: PendingAttr[] = [];
    let pendingSlotsWithLines: PendingSlot[] = [];
    let pendingComponentName: string | null = null;
    let currentSlot: ComponentSlot | null = null; // Track slot with do...end block
    let lastComponentLine = 0; // Track previous function to create boundaries between components

    lines.forEach((line, index) => {
      const trimmedLine = line.trim();

      // Pattern 1: Extract @doc for component
      if (trimmedLine.startsWith('@doc')) {
        // Match: @doc "Component description"
        const docMatch = /@doc\s+["']([^"']+)["']/.exec(trimmedLine);
        if (docMatch) {
          currentDoc = docMatch[1];
        }
      }

      // Pattern 2: Component function definition
      // Match: def component_name(assigns) do
      const componentPattern = /^(?:def|defp)\s+([a-z_][a-z0-9_]*)\s*\(\s*(?:[^)]*=\s*)?(?:assigns|_assigns)\s*\)\s+do/;
      const componentMatch = componentPattern.exec(trimmedLine);

      if (componentMatch) {
        const componentName = componentMatch[1];

        // Check if this line or next few lines contain ~H sigil (indicates it's a component)
        let hasHEExSigil = false;

        // First check current line (for inline definitions like: def button(assigns), do: ~H"...")
        if (line.includes('~H"') || line.includes("~H'") || line.includes('~H"""') || line.includes("~H'''")) {
          hasHEExSigil = true;
        }

        // Then check next 10 lines
        if (!hasHEExSigil) {
          for (let i = index + 1; i < Math.min(index + 10, lines.length); i++) {
            if (lines[i].includes('~H"') || lines[i].includes("~H'") ||
                lines[i].includes('~H"""') || lines[i].includes("~H'''")) {
              hasHEExSigil = true;
              break;
            }
          }
        }

        if (!hasHEExSigil) {
          // Likely a multi-clause component where this clause delegates to one with ~H.
          // Preserve pending attrs/slots so they can attach to the clause that renders.
          if (!pendingComponentName) {
            pendingComponentName = componentName;
          } else if (pendingComponentName !== componentName) {
            // New function name encountered without HEEx - just update the name, keep attrs
            pendingComponentName = componentName;
          }
          return;
        }

        // For HEEx clauses, find attrs/slots within 20 lines BEFORE this function
        const componentLine = index + 1;
        const proximityWindow = 20;

        // Get attrs that are within proximity window (within 20 lines before this function)
        // AND after the previous component (to prevent attrs leaking between components)
        const relevantAttrs = pendingAttributesWithLines
          .filter(pa => {
            const distance = componentLine - pa.line;
            return distance > 0 && distance <= proximityWindow && pa.line > lastComponentLine;
          })
          .map(pa => pa.attr);

        // Get slots that are within proximity window
        // AND after the previous component (to prevent slots leaking between components)
        const relevantSlots = pendingSlotsWithLines
          .filter(ps => {
            const distance = componentLine - ps.line;
            return distance > 0 && distance <= proximityWindow && ps.line > lastComponentLine;
          })
          .map(ps => ps.slot);

        // This is a component function
        currentComponent = {
          name: componentName,
          moduleName,
          filePath,
          line: componentLine,
          attributes: relevantAttrs, // Include attrs within proximity window
          slots: relevantSlots,       // Include slots within proximity window
          doc: currentDoc || undefined,
        };

        currentDoc = null; // Reset doc after using it
        pendingComponentName = null;

        // DON'T clear pending arrays - let subsequent functions use their nearby attrs
        // Only remove attrs that are now "too far away" (more than 30 lines old)
        const maxAge = 30;
        pendingAttributesWithLines = pendingAttributesWithLines.filter(pa =>
          componentLine - pa.line <= maxAge
        );
        pendingSlotsWithLines = pendingSlotsWithLines.filter(ps =>
          componentLine - ps.line <= maxAge
        );

        // Update lastComponentLine to create boundary for next component
        lastComponentLine = componentLine;
      }

      // Pattern 3: attr declarations (can be before OR inside component function)
      // Supports both atom types (:string) and module/struct types (MyApp.User)
      const attrLinePattern = /^attr\s+:([a-z_][a-z0-9_]*)\s*,\s*(.+)$/;
      const attrLineMatch = attrLinePattern.exec(trimmedLine);

      if (attrLineMatch) {
        const attrName = attrLineMatch[1];
        const rest = attrLineMatch[2];

        // Split rest into type expression and options (comma-separated, respecting brackets/quotes)
        let splitIndex = -1;
        let depth = 0;
        let inString: string | null = null;

        for (let i = 0; i < rest.length; i++) {
          const char = rest[i];

          if (inString) {
            if (char === inString && rest[i - 1] !== '\\') {
              inString = null;
            }
            continue;
          }

          if (char === '"' || char === "'") {
            inString = char;
            continue;
          }

          if (char === '{' || char === '[' || char === '(') {
            depth++;
            continue;
          }

          if (char === '}' || char === ']' || char === ')') {
            if (depth > 0) {
              depth--;
            }
            continue;
          }

          if (char === ',' && depth === 0) {
            splitIndex = i;
            break;
          }
        }

        const typeExpression =
          splitIndex === -1 ? rest.trim() : rest.slice(0, splitIndex).trim();
        const options =
          splitIndex === -1 ? '' : rest.slice(splitIndex + 1).trim();

        if (typeExpression.length > 0) {
          const rawType = typeExpression;
          let normalizedType = rawType.startsWith(':')
            ? rawType.slice(1)
            : rawType;

          if (normalizedType.endsWith('.t()')) {
            normalizedType = normalizedType.slice(0, -4);
          } else if (normalizedType.endsWith('.t')) {
            normalizedType = normalizedType.slice(0, -2);
          }

          const attribute: ComponentAttribute = {
            name: attrName,
            type: normalizedType,
            rawType,
            required: options.includes('required: true'),
          };

          // Extract default value
          const defaultMatch = /default:\s*([^,]+)/.exec(options);
          if (defaultMatch) {
            attribute.default = defaultMatch[1].trim();
          }

          // Extract values array for enums
          const valuesMatch = /values:\s*\[([^\]]+)\]/.exec(options);
          if (valuesMatch) {
            // Parse values like [:sm, :md, :lg] or ["primary", "secondary"] -> ["sm", "md", "lg"] or ["primary", "secondary"]
            attribute.values = valuesMatch[1]
              .split(',')
              .map(v => v.trim().replace(/^:/, '').replace(/^["']|["']$/g, ''));
          }

          // Extract doc
          const docMatch = /doc:\s*["']([^"']+)["']/.exec(options);
          if (docMatch) {
            attribute.doc = docMatch[1];
          }

          // Add to current slot if inside slot do...end block
          if (currentSlot) {
            currentSlot.attributes.push(attribute);
          }
          // Otherwise add to current component if inside function
          else if (currentComponent) {
            currentComponent.attributes.push(attribute);
          }
          // Otherwise add to pending with line number
          else {
            pendingAttributesWithLines.push({
              attr: attribute,
              line: index + 1  // Store line number for proximity-based assignment
            });
            // Reset tracked component name since new attrs likely belong to the next component definition.
            pendingComponentName = null;
          }
        }
      }

      // Pattern 4: slot declarations (can be before OR inside component function)
      // Match: slot :inner_block, required: true
      // Also supports: slot :header do ... end (with nested attributes)
      const slotPattern = /^slot\s+:([a-z_][a-z0-9_]*)(?:\s*,\s*(.+?))?\s*(do)?$/;
      const slotMatch = slotPattern.exec(trimmedLine);

      if (slotMatch) {
        const slotName = slotMatch[1];
        const options = slotMatch[2] || '';
        const hasDoBlock = slotMatch[3] === 'do';

        const slot: ComponentSlot = {
          name: slotName,
          required: options.includes('required: true'),
          attributes: [], // Initialize empty attributes array
        };

        // Extract doc
        const docMatch = /doc:\s*["']([^"']+)["']/.exec(options);
        if (docMatch) {
          slot.doc = docMatch[1];
        }

        // If slot has do...end block, track it so attrs can be added to it
        if (hasDoBlock) {
          currentSlot = slot;
        }
        // Otherwise add immediately to current component or pending
        else {
          if (currentComponent) {
            currentComponent.slots.push(slot);
          } else {
            pendingSlotsWithLines.push({
              slot: slot,
              line: index + 1  // Store line number for proximity-based assignment
            });
          }
        }
      }

      // Pattern 5: End of function/block
      if (trimmedLine === 'end') {
        // If we're inside a slot do...end block, finalize the slot
        if (currentSlot) {
          if (currentComponent) {
            currentComponent.slots.push(currentSlot);
          } else {
            pendingSlotsWithLines.push({
              slot: currentSlot,
              line: index + 1  // Store line number for proximity-based assignment
            });
          }
          currentSlot = null;
        }
        // If we're inside a component, save the component
        else if (currentComponent) {
          // Add ALL components, even without attributes/slots
          // This allows discovery of simple components
          components.push(currentComponent);
          currentComponent = null;
        }
      }
    });

    // Deduplicate function clauses: Multiple function clauses with the same name
    // (e.g., def input(%{field: ...}), def input(%{type: "checkbox"}), etc.)
    // should be merged into ONE component with ALL attrs/slots
    const deduplicatedComponents = this.deduplicateFunctionClauses(components);

    timer.stop({ file: path.relative(this.workspaceRoot || '', filePath), count: deduplicatedComponents.length });
    return deduplicatedComponents;
  }

  /**
   * Deduplicate function clauses
   *
   * In Elixir, a component can have multiple function clauses (pattern matching):
   *   def input(%{field: ...} = assigns) do ... end
   *   def input(%{type: "checkbox"} = assigns) do ... end
   *   def input(assigns) do ... end
   *
   * All clauses share the SAME attr/slot declarations at the top.
   * This method merges all clauses into ONE component.
   */
  private deduplicateFunctionClauses(components: PhoenixComponent[]): PhoenixComponent[] {
    // Group components by unique key: moduleName + componentName
    const groupedByName = new Map<string, PhoenixComponent[]>();

    for (const component of components) {
      const key = `${component.moduleName}.${component.name}`;
      if (!groupedByName.has(key)) {
        groupedByName.set(key, []);
      }
      groupedByName.get(key)!.push(component);
    }

    const deduplicated: PhoenixComponent[] = [];

    for (const [key, clauses] of groupedByName) {
      if (clauses.length === 1) {
        // Single clause - no deduplication needed
        deduplicated.push(clauses[0]);
      } else {
        // Multiple clauses - merge them into one component
        const firstClause = clauses[0];

        // Collect all attrs from all clauses
        const allAttrs: ComponentAttribute[] = [];
        const attrKeys = new Set<string>();

        for (const clause of clauses) {
          for (const attr of clause.attributes) {
            if (!attrKeys.has(attr.name)) {
              allAttrs.push(attr);
              attrKeys.add(attr.name);
            }
          }
        }

        // Collect all slots from all clauses
        const allSlots: ComponentSlot[] = [];
        const slotKeys = new Set<string>();

        for (const clause of clauses) {
          for (const slot of clause.slots) {
            if (!slotKeys.has(slot.name)) {
              allSlots.push(slot);
              slotKeys.add(slot.name);
            }
          }
        }

        // Create merged component (use first clause's metadata)
        const mergedComponent: PhoenixComponent = {
          name: firstClause.name,
          moduleName: firstClause.moduleName,
          filePath: firstClause.filePath,
          line: firstClause.line,
          attributes: allAttrs,
          slots: allSlots,
          doc: firstClause.doc,
        };

        deduplicated.push(mergedComponent);
      }
    }

    return deduplicated;
  }

  /**
   * Update components for a specific file
   */
  /**
   * Update file in registry using async parser (tries Elixir AST first)
   */
  async updateFileAsync(filePath: string, content: string): Promise<void> {
    const normalized = this.normalizePath(filePath);

    if (isBuiltinResourcePath(normalized)) {
      this.ensureBuiltinComponents();
      this.fileHashes.set(normalized, 'builtin');
      return;
    }

    const hash = computeHash(content);
    const previousHash = this.fileHashes.get(normalized);

    if (previousHash === hash && this.components.has(normalized)) {
      return;
    }

    const timer = new PerfTimer('components.updateFileAsync');
    const components = await this.parseFileAsync(normalized, content);

    // Always update the registry, even if parsing returned 0 components
    // This prevents registry corruption due to transient parsing failures
    this.components.set(normalized, components);
    this.fileHashes.set(normalized, hash);

    if (components.length > 0) {
      debugLog('registry', `[ComponentsRegistry] Found ${components.length} components in ${path.basename(filePath)}: ${components.map(c => c.name).join(', ')}`);
    } else {
      debugLog('registry', `[ComponentsRegistry] No components found in ${path.basename(filePath)}, but keeping in registry to prevent deletion`);
    }

    timer.stop({ file: path.relative(this.workspaceRoot || '', filePath), components: components.length });
  }

  /**
   * Update file in registry (synchronous, uses regex parser)
   */
  updateFile(filePath: string, content: string) {
    const normalized = this.normalizePath(filePath);

    if (isBuiltinResourcePath(normalized)) {
      this.ensureBuiltinComponents();
      this.fileHashes.set(normalized, 'builtin');
      return;
    }

    const hash = computeHash(content);
    const previousHash = this.fileHashes.get(normalized);

    if (previousHash === hash && this.components.has(normalized)) {
      return;
    }

    const timer = new PerfTimer('components.updateFile');
    const components = this.parseFile(normalized, content);

    // Always update the registry, even if parsing returned 0 components
    // This prevents registry corruption due to transient parsing failures
    this.components.set(normalized, components);
    this.fileHashes.set(normalized, hash);

    if (components.length > 0) {
      debugLog('registry', `[ComponentsRegistry] Found ${components.length} components in ${path.basename(filePath)}: ${components.map(c => c.name).join(', ')}`);
    } else {
      debugLog('registry', `[ComponentsRegistry] No components found in ${path.basename(filePath)}, but keeping in registry to prevent deletion`);
    }

    timer.stop({ file: path.relative(this.workspaceRoot || '', filePath), components: components.length });
  }

  /**
   * Remove a file from the registry
   */
  removeFile(filePath: string) {
    const normalized = this.normalizePath(filePath);

    if (isBuiltinResourcePath(normalized)) {
      return;
    }

    // Single existence check with proper error handling
    // Don't remove from registry if file still exists
    try {
      if (fs.existsSync(normalized)) {
        return;
      }
    } catch {
      // If we can't check (e.g., permission error), assume file is gone
      // Better to remove from registry than keep stale entry
    }

    const hadComponents = this.components.has(normalized);
    const componentsCount = hadComponents ? this.components.get(normalized)?.length || 0 : 0;

    this.components.delete(normalized);
    this.fileHashes.delete(normalized);

    if (hadComponents) {
      debugLog('definition', `[ComponentsRegistry] Removed ${normalized} from registry (had ${componentsCount} components)`);
    }
  }

  /**
   * Get all components from all files
   */
  getAllComponents(): PhoenixComponent[] {
    const allComponents: PhoenixComponent[] = [];
    this.components.forEach((components) => {
      allComponents.push(...components);
    });
    return allComponents;
  }

  /**
   * Check if a component exists in the registry
   */
  componentExists(componentName: string): boolean {
    for (const components of this.components.values()) {
      if (components.some(comp => comp.name === componentName)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Get a specific component by name
   */
  getComponent(componentName: string): PhoenixComponent | null {
    for (const components of this.components.values()) {
      const component = components.find(comp => comp.name === componentName);
      if (component) {
        return component;
      }
    }
    return null;
  }

  /**
   * Get component by module and name (for remote components like <Module.component>)
   */
  getComponentByModule(moduleName: string, componentName: string): PhoenixComponent | null {
    for (const components of this.components.values()) {
      const component = components.find(
        comp => comp.moduleName === moduleName && comp.name === componentName
      );
      if (component) {
        return component;
      }
    }
    return null;
  }

  /**
   * Get all components from a specific module
   */
  getComponentsFromModule(moduleName: string): PhoenixComponent[] {
    const result: PhoenixComponent[] = [];
    this.components.forEach((components) => {
      components.forEach(comp => {
        if (comp.moduleName === moduleName) {
          result.push(comp);
        }
      });
    });
    return result;
  }

  /**
   * Get components from a specific file
   */
  getComponentsFromFile(filePath: string): PhoenixComponent[] {
    return this.components.get(this.normalizePath(filePath)) || [];
  }

  /**
   * Find all component module files for a template
   * For example: app_web/live/user_live/index.html.heex ->
   *   [app_web/components/core_components.ex, app_web/components/ui_components.ex, ...]
   */
  findComponentModulesForTemplate(templatePath: string): string[] {
    // Ensure workspaceRoot is set
    if (!this.workspaceRoot) {
      debugLog('definition', `[findComponentModulesForTemplate] WARNING: workspaceRoot not set, returning empty array`);
      return [];
    }

    // Extract the app name from path (e.g., "app_web" from "lib/app_web/live/...")
    const pathParts = templatePath.split(path.sep);
    const libIndex = pathParts.indexOf('lib');

    if (libIndex === -1 || libIndex + 1 >= pathParts.length) {
      debugLog('definition', `[findComponentModulesForTemplate] Could not extract app name from ${templatePath}`);
      return [];
    }

    const appWeb = pathParts[libIndex + 1]; // e.g., "app_web"
    const componentFiles: Set<string> = new Set();

    // Check components directory
    const componentsDir = this.normalizePath(path.join(this.workspaceRoot, 'lib', appWeb, 'components'));
    debugLog('definition', `[findComponentModulesForTemplate] Checking components dir: ${componentsDir}`);

    if (fs.existsSync(componentsDir) && fs.statSync(componentsDir).isDirectory()) {
      const visitStack: string[] = [componentsDir];

      while (visitStack.length > 0) {
        const currentDir = visitStack.pop()!;
        try {
          const entries = fs.readdirSync(currentDir, { withFileTypes: true });
          for (const entry of entries) {
            const fullPath = this.normalizePath(path.join(currentDir, entry.name));
            if (entry.isDirectory()) {
              visitStack.push(fullPath);
            } else if (entry.isFile() && entry.name.endsWith('.ex')) {
              componentFiles.add(fullPath);
              debugLog('definition', `[findComponentModulesForTemplate] Added component file: ${fullPath}`);
            }
          }
        } catch (err) {
          debugLog('definition', `[findComponentModulesForTemplate] Error reading ${currentDir}: ${err}`);
        }
      }
    }

    // Also check for single components.ex file
    const singleComponentFile = this.normalizePath(path.join(this.workspaceRoot, 'lib', appWeb, 'components.ex'));
    if (fs.existsSync(singleComponentFile)) {
      componentFiles.add(singleComponentFile);
      debugLog('definition', `[findComponentModulesForTemplate] Added single component file: ${singleComponentFile}`);
    }

    // If template itself is a component module, include it
    if (templatePath.endsWith('.ex') || templatePath.endsWith('.exs')) {
      const normalized = this.normalizePath(templatePath);
      componentFiles.add(normalized);
      debugLog('definition', `[findComponentModulesForTemplate] Added template file itself: ${normalized}`);
    }

    const result = Array.from(componentFiles);
    debugLog('definition', `[findComponentModulesForTemplate] Returning ${result.length} module files for ${templatePath}`);
    return result;
  }

  /**
   * Get components relevant to a specific template
   * Prioritizes components from the same context
   */
  getComponentsForTemplate(templatePath: string): {
    primary: PhoenixComponent[];
    secondary: PhoenixComponent[];
  } {
    const moduleFiles = this.findComponentModulesForTemplate(templatePath);
    const primary: PhoenixComponent[] = [];
    const secondary: PhoenixComponent[] = [];

    // Debug logging to identify path mismatches
    const registryKeys = Array.from(this.components.keys());
    debugLog('definition', `[getComponentsForTemplate] Template: ${templatePath}`);
    debugLog('definition', `[getComponentsForTemplate] ModuleFiles (${moduleFiles.length}): ${moduleFiles.join(', ')}`);
    debugLog('definition', `[getComponentsForTemplate] Registry keys (${registryKeys.length}): ${registryKeys.join(', ')}`);

    // Create a Set of normalized module file paths for efficient lookup
    // Re-normalize moduleFiles to ensure consistency with registry keys
    const normalizedModuleFiles = new Set(moduleFiles.map(f => this.normalizePath(f)));
    debugLog('definition', `[getComponentsForTemplate] Normalized moduleFiles: ${Array.from(normalizedModuleFiles).join(', ')}`);

    moduleFiles.forEach(filePath => {
      this.memoizeFileFromDisk(filePath);
    });

    this.components.forEach((components, filePath) => {
      // Re-normalize the registry key to ensure consistency
      const normalizedFilePath = this.normalizePath(filePath);
      const isInModuleFiles = normalizedModuleFiles.has(normalizedFilePath);
      debugLog('definition', `[getComponentsForTemplate] Checking ${filePath} (normalized: ${normalizedFilePath}): ${isInModuleFiles ? 'PRIMARY' : 'SECONDARY'} (${components.length} components: ${components.map(c => c.name).join(', ')})`);

      if (isInModuleFiles) {
        primary.push(...components);
      } else {
        secondary.push(...components);
      }
    });

    debugLog('definition', `[getComponentsForTemplate] Result: ${primary.length} primary, ${secondary.length} secondary`);
    return { primary, secondary };
  }

  /**
   * Resolve the best matching component for a given template context
   */
  resolveComponent(
    templatePath: string,
    componentName: string,
    options: { moduleContext?: string; fileContent?: string } = {}
  ): PhoenixComponent | null {
    const { moduleContext, fileContent } = options;
    const importInfo = this.getImportInfoForTemplate(templatePath, fileContent);
    const moduleFilesForTemplate = this.findComponentModulesForTemplate(templatePath);

    const tryResolveFromModule = (moduleName: string | null | undefined): PhoenixComponent | null => {
      if (!moduleName) {
        return null;
      }
      return this.getComponentByModule(moduleName, componentName);
    };

    // 1. If we have a module context (<Module.component>), resolve aliases first
    if (moduleContext) {
      const resolvedModule = this.resolveModuleFromContext(moduleContext, importInfo);
      const moduleComponent = tryResolveFromModule(resolvedModule);
      if (moduleComponent) {
        debugLog(
          'definition',
          `resolveComponent: <.${componentName}> matched via module context ${resolvedModule} -> ${moduleComponent.filePath}`
        );
        return moduleComponent;
      }
    }

    // 2. Prefer components from the same context (primary set)
    const { primary, secondary } = this.getComponentsForTemplate(templatePath);
    const primaryMatch = primary.find(component => component.name === componentName);
    if (primaryMatch) {
      debugLog(
        'definition',
        `resolveComponent: <.${componentName}> matched primary component ${primaryMatch.moduleName} (${primaryMatch.filePath})`
      );
      return primaryMatch;
    }

    // 3. Check imported or aliased modules for matching components
    const importedModules = new Set<string>();
    importInfo.importedModules.forEach(moduleName => importedModules.add(moduleName));
    importInfo.aliasedModules.forEach(fullModule => importedModules.add(fullModule));

    for (const moduleName of importedModules) {
      const component = tryResolveFromModule(moduleName);
      if (component) {
        debugLog(
          'definition',
          `resolveComponent: <.${componentName}> matched imported module ${moduleName} (${component.filePath})`
        );
        return component;
      }
    }

    // 4. Check secondary components (other modules in workspace)
    const secondaryMatch = secondary.find(component => component.name === componentName);
    if (secondaryMatch) {
      debugLog(
        'definition',
        `resolveComponent: <.${componentName}> matched secondary component ${secondaryMatch.moduleName} (${secondaryMatch.filePath})`
      );
      return secondaryMatch;
    }

    // 5. Fallback to global lookup
    const globalMatch = this.getComponent(componentName);
    if (globalMatch) {
      debugLog(
        'definition',
        `resolveComponent: <.${componentName}> matched global component ${globalMatch.moduleName} (${globalMatch.filePath})`
      );
    } else {
      const moduleSummary = moduleFilesForTemplate.length > 0 ? moduleFilesForTemplate.join(', ') : '<none>';
      const primarySummary = primary.length > 0 ? primary.map(c => `${c.moduleName}.${c.name}`).join(', ') : '<empty>';
      const secondarySummary = secondary.length > 0 ? secondary.map(c => `${c.moduleName}.${c.name}`).join(', ') : '<empty>';
      const importsSummary = importedModules.size > 0 ? Array.from(importedModules).join(', ') : '<none>';
      debugLog(
        'definition',
        `resolveComponent: <.${componentName}> not found for template ${templatePath}\n` +
          `  moduleFiles: ${moduleSummary}\n` +
          `  primary components: ${primarySummary}\n` +
          `  secondary components: ${secondarySummary}\n` +
          `  imported/aliased modules: ${importsSummary}`
      );
    }
    return globalMatch;
  }

  /**
   * Parse import and alias statements from an Elixir file
   * Examples:
   *   import MyAppWeb.CustomComponents
   *   alias MyAppWeb.{CoreComponents, CustomComponents}
   */
  parseImports(filePath: string, content?: string): ImportInfo {
    const importedModules = new Set<string>();
    const aliasedModules = new Map<string, string>();

    // Read file if content not provided
    let fileContent = content;
    if (!fileContent) {
      try {
        fileContent = fs.readFileSync(filePath, 'utf-8');
      } catch (err) {
        return { importedModules, aliasedModules };
      }
    }

    const lines = fileContent.split('\n');

    const addImport = (moduleName: string) => {
      if (moduleName && moduleName.length > 0) {
        importedModules.add(moduleName);
      }
    };

    for (const line of lines) {
      const trimmedLine = line.trim();

      // Pattern 1: import Module.Name
      const importPattern = /^\s*import\s+([\w.]+)/;
      const importMatch = importPattern.exec(trimmedLine);
      if (importMatch) {
        addImport(importMatch[1]);
        continue;
      }

      // Pattern 2: alias Module.{Sub1, Sub2, Sub3}
      const aliasGroupPattern = /^\s*alias\s+([\w.]+)\.{([^}]+)}/;
      const aliasGroupMatch = aliasGroupPattern.exec(trimmedLine);
      if (aliasGroupMatch) {
        const baseModule = aliasGroupMatch[1]; // e.g., "MyAppWeb"
        const subModules = aliasGroupMatch[2]
          .split(',')
          .map(s => s.trim())
          .filter(s => s.length > 0); // Filter out empty strings from malformed input
        for (const subModule of subModules) {
          const fullModule = `${baseModule}.${subModule}`;
          aliasedModules.set(subModule, fullModule);
        }
        continue;
      }

      // Pattern 3: alias Module.Name
      const aliasSinglePattern = /^\s*alias\s+([\w.]+)(?:\s+as\s+([\w]+))?/;
      const aliasSingleMatch = aliasSinglePattern.exec(trimmedLine);
      if (aliasSingleMatch) {
        const fullModule = aliasSingleMatch[1];
        const aliasName = aliasSingleMatch[2] || fullModule.split('.').pop() || fullModule;
        aliasedModules.set(aliasName, fullModule);
        continue;
      }

      const usePattern = /^\s*use\s+([\w.]+)(?:\s*,\s*:(\w+))?/;
      const useMatch = usePattern.exec(trimmedLine);
      if (useMatch) {
        const usedModule = useMatch[1];
        const role = useMatch[2];

        addImport(usedModule);

        if (role === 'html') {
          addImport(`${usedModule}.CoreComponents`);
          addImport('Phoenix.Component');
          addImport('Phoenix.LiveView.JS');
        } else if (role === 'live_view' || role === 'live_component') {
          addImport('Phoenix.Component');
          addImport('Phoenix.LiveView');
          addImport('Phoenix.LiveView.JS');
        } else if (!role && usedModule === 'Phoenix.Component') {
          addImport('Phoenix.LiveView.JS');
        }
      }
    }

    return { importedModules: Array.from(importedModules), aliasedModules };
  }

  /**
   * Resolve an aliased module name to its fully-qualified module
   */
  private resolveModuleFromContext(moduleContext: string, importInfo: ImportInfo): string {
    if (!moduleContext) {
      return moduleContext;
    }

    const parts = moduleContext.split('.');
    const rootAlias = parts[0];
    const aliasedModule = importInfo.aliasedModules.get(rootAlias);

    if (!aliasedModule) {
      return moduleContext;
    }

    if (parts.length === 1) {
      return aliasedModule;
    }

    return `${aliasedModule}.${parts.slice(1).join('.')}`;
  }

  /**
   * Get import information for the current template or module file
   */
  private getImportInfoForTemplate(templatePath: string, fileContent?: string): ImportInfo {
    // For HEEx templates, attempt to read the associated HTML module
    if (templatePath.endsWith('.heex')) {
      const htmlModule = this.getHtmlModuleForTemplate(templatePath);
      if (htmlModule) {
        return this.parseImports(htmlModule);
      }
      return { importedModules: [], aliasedModules: new Map<string, string>() };
    }

    // For Elixir modules, parse imports from the file (using in-memory content if provided)
    if (templatePath.endsWith('.ex') || templatePath.endsWith('.exs')) {
      return this.parseImports(templatePath, fileContent);
    }

    return { importedModules: [], aliasedModules: new Map<string, string>() };
  }

  /**
   * Get the HTML module file for a template
   * Example: lib/app_web/controllers/page_html/index.html.heex
   *       -> lib/app_web/controllers/page_html.ex
   */
  getHtmlModuleForTemplate(templatePath: string): string | null {
    const pathParts = templatePath.split(path.sep);

    // Find the .html.heex file in the path
    const heexFileIndex = pathParts.findIndex(part => part.endsWith('.html.heex'));

    if (heexFileIndex === -1 || heexFileIndex === 0) {
      return null;
    }

    // The parent directory usually becomes the module file
    // e.g., page_html/index.html.heex -> page_html.ex
    const moduleDir = pathParts[heexFileIndex - 1];

    // Build path to HTML module
    const modulePath = [...pathParts.slice(0, heexFileIndex - 1), `${moduleDir}.ex`];
    const htmlModulePath = modulePath.join(path.sep);

    if (fs.existsSync(htmlModulePath)) {
      return this.normalizePath(htmlModulePath);
    }

    return null;
  }

  /**
   * Scan workspace for component files
   */
  async scanWorkspace(workspaceRoot: string): Promise<void> {
    this.workspaceRoot = workspaceRoot;

    const filesToScan: Array<{ path: string; content: string }> = [];

    const scanDirectory = (dir: string) => {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);

          // Skip common excluded directories
          if (entry.isDirectory()) {
            const dirName = entry.name;
            if (
              dirName === 'node_modules' ||
              dirName === 'deps' ||
              dirName === '_build' ||
              dirName === '.git' ||
              dirName === 'assets'
            ) {
              continue;
            }
            scanDirectory(fullPath);
          } else if (entry.isFile() && (entry.name.endsWith('.ex') || entry.name.endsWith('.exs'))) {
            // Focus on component files - be more precise about what we scan
            // Normalize path for cross-platform compatibility (Windows uses backslashes)
            const normalizedPath = fullPath.replace(/\\/g, '/');
            const isComponentFile =
              normalizedPath.includes('/components/') ||        // In components folder
              entry.name.endsWith('_components.ex') ||    // Component module files
              entry.name === 'core_components.ex' ||      // Core components
              (normalizedPath.includes('_web/') && entry.name.endsWith('_html.ex')); // HTML modules (for import checking)

            if (isComponentFile) {
              try {
                const content = fs.readFileSync(fullPath, 'utf-8');
                filesToScan.push({ path: fullPath, content });
              } catch (err) {
                // Ignore files we can't read
              }
            }
          }
        }
      } catch (err) {
        // Ignore directories we can't read
      }
    };

    // First, collect all files to scan
    time('components.scanWorkspace.collect', () => scanDirectory(workspaceRoot), { root: workspaceRoot });

    // Then parse them asynchronously (uses Elixir parser with fallback)
    console.log(`[Phoenix Pulse] Scanning ${filesToScan.length} component files with ${this.useElixirParser ? 'Elixir AST parser' : 'regex parser'}`);

    for (const file of filesToScan) {
      await this.updateFileAsync(file.path, file.content);
    }

    console.log(`[Phoenix Pulse] Scan complete - found ${this.getAllComponents().length} total components`);
  }

  /**
   * Get attributes for the component at a specific offset in a file
   * Used for @ and assigns. autocomplete
   * @param filePath - Path to the Elixir file
   * @param offset - Character offset in the file
   * @param content - Optional file content (if not provided, will read from disk)
   * @returns Component attributes if cursor is inside a component function, null otherwise
   */
  getCurrentComponent(
    filePath: string,
    offset: number,
    content?: string
  ): PhoenixComponent | null {
    // Read file if content not provided
    let fileContent = content;
    if (!fileContent) {
      try {
        fileContent = fs.readFileSync(filePath, 'utf-8');
      } catch (err) {
        return null;
      }
    }

    const lines = fileContent.split('\n');
    let currentLine = 0;
    let currentOffset = 0;

    // Find which line the offset is on
    for (let i = 0; i < lines.length; i++) {
      const lineLength = lines[i].length + 1; // +1 for newline
      if (currentOffset + lineLength > offset) {
        currentLine = i;
        break;
      }
      currentOffset += lineLength;
    }

    // Search backwards to find the component function definition
    let componentStartLine = -1;
    let componentName = '';

    for (let i = currentLine; i >= 0; i--) {
      const trimmedLine = lines[i].trim();
      const componentPattern = /^(?:def|defp)\s+([a-z_][a-z0-9_]*)\s*\(\s*assigns\s*\)\s+do/;
      const match = componentPattern.exec(trimmedLine);

      if (match) {
        componentStartLine = i;
        componentName = match[1];
        break;
      }
    }

    // If we didn't find a component definition, return null
    if (componentStartLine === -1) {
      return null;
    }

    // Search forward to find the end of this component function
    let componentEndLine = -1;
    let depth = 1; // We're inside the function already

    for (let i = componentStartLine + 1; i < lines.length; i++) {
      const trimmedLine = lines[i].trim();

      // Count do/end depth
      if (trimmedLine.match(/\bdo\b/)) {
        depth++;
      }
      // Match 'end' as a word boundary (not inside another word)
      if (trimmedLine.match(/^\s*end\b/)) {
        depth--;
        if (depth === 0) {
          componentEndLine = i;
          break;
        }
      }
    }

    // If we didn't find the end, assume the function continues to end of file
    // This handles the case where user is still typing
    if (componentEndLine === -1) {
      componentEndLine = lines.length - 1;
    }

    // Verify cursor is within component bounds
    if (currentLine > componentEndLine) {
      return null;
    }

    // Re-parse the current content to get fresh component data
    // This ensures we capture attributes declared before the function in real-time
    const components = this.parseFile(filePath, fileContent);

    // Find the component by name and line number
    const component = components.find(comp =>
      comp.name === componentName &&
      comp.line === componentStartLine + 1 // +1 because line numbers are 1-indexed
    );

    return component || null;
  }

  /**
   * Get attributes for the component at a specific offset in a file
   * Used for @ and assigns. autocomplete
   */
  getCurrentComponentAttributes(filePath: string, offset: number, content?: string): ComponentAttribute[] | null {
    const component = this.getCurrentComponent(filePath, offset, content);
    if (!component) {
      return null;
    }
    return component.attributes;
  }
  private ensureBuiltinComponents() {
    if (this.builtinsRegistered) {
      return;
    }
    this.components.set('__phoenix_builtins__', BUILTIN_COMPONENTS);
    this.fileHashes.set(NORMALIZED_BUILTIN_PHOENIX_COMPONENT_PATH, 'builtin');
    this.builtinsRegistered = true;
  }

  private memoizeFileFromDisk(filePath: string) {
    const normalized = this.normalizePath(filePath);

    if (isBuiltinResourcePath(normalized)) {
      this.ensureBuiltinComponents();
      return;
    }

    const existing = this.components.get(normalized);
    if (existing && existing.length > 0) {
      return;
    }

    try {
      if (!fs.existsSync(normalized)) {
        return;
      }
      const content = fs.readFileSync(normalized, 'utf-8');
      const components = this.parseFile(normalized, content);
      this.components.set(normalized, components);
      this.fileHashes.set(normalized, computeHash(content));
      if (components.length > 0) {
        debugLog(
          'registry',
          `[ComponentsRegistry] Loaded ${components.length} components from ${path.basename(normalized)}`
        );
      } else {
        debugLog(
          'registry',
          `[ComponentsRegistry] File ${path.basename(normalized)} has no components after memoization`
        );
      }
    } catch (error) {
      debugLog(
        'definition',
        `[ComponentsRegistry] Failed to memoize ${normalized}: ${error}`
      );
    }
  }

  private isWithinWorkspace(filePath: string): boolean {
    if (!this.workspaceRoot) {
      return false;
    }

    const relative = path.relative(this.workspaceRoot, filePath);
    return !!relative && !relative.startsWith('..') && !path.isAbsolute(relative);
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const componentsArray: Array<[string, PhoenixComponent[]]> = [];

    if (this.components) {
      for (const [filePath, components] of this.components.entries()) {
        // Skip built-in components (they're always re-registered)
        if (BUILTIN_RESOURCE_PATHS.has(filePath)) {
          continue;
        }
        componentsArray.push([filePath, components]);
      }
    }

    const fileHashesObj: Record<string, string> = {};
    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        if (!BUILTIN_RESOURCE_PATHS.has(filePath)) {
          fileHashesObj[filePath] = hash;
        }
      }
    }

    return {
      components: componentsArray,
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

    // Clear current data (except builtins)
    if (this.components) {
      for (const filePath of this.components.keys()) {
        if (!BUILTIN_RESOURCE_PATHS.has(filePath)) {
          this.components.delete(filePath);
        }
      }
    }
    if (this.fileHashes) {
      for (const filePath of this.fileHashes.keys()) {
        if (!BUILTIN_RESOURCE_PATHS.has(filePath)) {
          this.fileHashes.delete(filePath);
        }
      }
    }

    // Load components
    if (cacheData.components && Array.isArray(cacheData.components)) {
      for (const [filePath, components] of cacheData.components) {
        this.components.set(filePath, components);
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

    console.log(`[ComponentsRegistry] Loaded ${this.getAllComponents().length} components from cache`);
  }
}

const BUILTIN_COMPONENTS: PhoenixComponent[] = [
  {
    name: 'link',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('link'),
    doc: 'Phoenix.Component.link/1 – Generates an anchor tag that supports LiveView-aware navigation.',
    attributes: [
      { name: 'navigate', type: 'string', required: false, doc: 'Use VerifiedRoutes: `navigate={~p"/path"}`' },
      { name: 'patch', type: 'string', required: false, doc: 'Use VerifiedRoutes: `patch={~p"/path"}`' },
      { name: 'href', type: 'string', required: false, doc: 'External/legacy target. Prefer `navigate`/`patch` with VerifiedRoutes.' },
      { name: 'method', type: 'string', required: false },
      { name: 'class', type: 'string', required: false },
      { name: 'replace', type: 'boolean', required: false },
    ],
    slots: [
      { name: 'inner_block', required: true, attributes: [] },
    ],
  },
  {
    name: 'live_patch',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('live_patch'),
    doc: 'Phoenix.Component.live_patch/1 – Generates a patch navigation link within the same LiveView.',
    attributes: [
      { name: 'patch', type: 'string', required: true, doc: 'Use VerifiedRoutes: `patch={~p"/path"}`' },
      { name: 'class', type: 'string', required: false },
      { name: 'replace', type: 'boolean', required: false },
    ],
    slots: [
      { name: 'inner_block', required: true, attributes: [] },
    ],
  },
  {
    name: 'live_redirect',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('live_redirect'),
    doc: 'Phoenix.Component.live_redirect/1 – Generates a redirect navigation link to another LiveView or controller.',
    attributes: [
      { name: 'navigate', type: 'string', required: true, doc: 'Use VerifiedRoutes: `navigate={~p"/path"}`' },
      { name: 'class', type: 'string', required: false },
      { name: 'replace', type: 'boolean', required: false },
    ],
    slots: [
      { name: 'inner_block', required: true, attributes: [] },
    ],
  },
  {
    name: 'live_component',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('live_component'),
    doc: 'Phoenix.Component.live_component/1 – Embeds a stateful LiveComponent from HEEx.',
    attributes: [
      { name: 'module', type: 'module', required: true, doc: 'LiveComponent module (e.g., `module={MyAppWeb.ModalComponent}`).' },
      { name: 'id', type: 'string', required: true },
      { name: ':for', type: 'any', required: false },
      { name: ':let', type: 'any', required: false },
    ],
    slots: [
      { name: 'inner_block', required: false, attributes: [] },
    ],
  },
  {
    name: 'form',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('form'),
    doc: 'Phoenix.Component.form/1 – Renders a HEEx form with support for :let assigns and action attributes.',
    attributes: [
      { name: 'for', type: 'any', required: true },
      { name: 'as', type: 'string', required: false },
      { name: 'id', type: 'string', required: false },
      { name: 'action', type: 'string', required: false },
      { name: 'method', type: 'string', required: false },
      { name: 'phx-submit', type: 'string', required: false },
      { name: 'phx-change', type: 'string', required: false },
      { name: ':let', type: 'any', required: false },
    ],
    slots: [
      { name: 'inner_block', required: true, attributes: [] },
      { name: 'actions', required: false, attributes: [] },
    ],
  },
  {
    name: 'inputs_for',
    moduleName: 'Phoenix.Component',
    filePath: BUILTIN_PHOENIX_COMPONENT_PATH,
    line: getBuiltinComponentLine('inputs_for'),
    doc: 'Phoenix.Component.inputs_for/1 – Iterates nested inputs for associations or embeds within a parent form.',
    attributes: [
      { name: 'field', type: 'any', required: true, doc: 'Form field or association (e.g., `field={f[:addresses]}`).' },
      { name: ':let', type: 'any', required: true, doc: 'Binding for the nested form (e.g., `:let={address_form}`).' },
      { name: 'for', type: 'any', required: false, doc: 'Explicit changeset/source for the nested inputs.' },
    ],
    slots: [
      { name: 'inner_block', required: true, attributes: [] },
    ],
  },
];
