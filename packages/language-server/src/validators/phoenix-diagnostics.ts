import * as fs from 'fs';
import * as path from 'path';
import { Diagnostic, DiagnosticSeverity, Range } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { EventsRegistry } from '../events-registry';
import { TemplatesRegistry } from '../templates-registry';

/**
 * Represents a Phoenix attribute found in a document
 */
interface PhoenixAttribute {
  name: string;
  value: string;
  range: Range;
  valueRange: Range; // Range of just the value part (for underlining)
}

/**
 * Attribute configuration type
 */
interface AttributeConfig {
  type: 'event' | 'selector' | 'debounce' | 'number' | 'enum' | 'none' | 'string';
  values?: string[];
  description: string;
}

/**
 * Known Phoenix LiveView attributes and their expected value types
 */
const KNOWN_PHOENIX_ATTRS: Record<string, AttributeConfig> = {
  // Event bindings - expect event name or JS command
  'phx-click': { type: 'event', description: 'Click event binding' },
  'phx-submit': { type: 'event', description: 'Form submit event binding' },
  'phx-change': { type: 'event', description: 'Input change event binding' },
  'phx-blur': { type: 'event', description: 'Blur event binding' },
  'phx-focus': { type: 'event', description: 'Focus event binding' },
  'phx-keydown': { type: 'event', description: 'Keydown event binding' },
  'phx-keyup': { type: 'event', description: 'Keyup event binding' },
  'phx-window-keydown': { type: 'event', description: 'Window keydown event binding' },
  'phx-window-keyup': { type: 'event', description: 'Window keyup event binding' },
  'phx-window-focus': { type: 'event', description: 'Window focus event binding' },
  'phx-window-blur': { type: 'event', description: 'Window blur event binding' },
  'phx-click-away': { type: 'event', description: 'Click away event binding' },
  'phx-capture-click': { type: 'event', description: 'Capture click event binding' },
  'phx-viewport-top': { type: 'event', description: 'Viewport top event binding' },
  'phx-viewport-bottom': { type: 'event', description: 'Viewport bottom event binding' },

  // Targeting & rate limiting - expect specific values
  'phx-target': { type: 'selector', description: 'Event target selector' },
  'phx-debounce': { type: 'debounce', description: 'Debounce time in ms or "blur"' },
  'phx-throttle': { type: 'number', description: 'Throttle time in ms' },

  // DOM operations - expect enum values
  'phx-update': { type: 'enum', values: ['replace', 'append', 'prepend', 'ignore', 'stream'], description: 'DOM update strategy' },
  'phx-remove': { type: 'none', description: 'Remove element on update' },
  'phx-mounted': { type: 'string', description: 'JS commands when element mounted' },

  // Hooks - expect hook name
  'phx-hook': { type: 'string', description: 'Client-side hook name' },

  // Feedback
  'phx-disable-with': { type: 'string', description: 'Text to show while processing' },
  'phx-feedback-for': { type: 'string', description: 'Input name for feedback association' },

  // Page events
  'phx-page-loading': { type: 'none', description: 'Page loading state' },
  'phx-connected': { type: 'string', description: 'CSS class when connected' },
  'phx-disconnected': { type: 'string', description: 'CSS class when disconnected' },

  // Navigation
  'phx-link': { type: 'enum', values: ['patch', 'navigate'], description: 'LiveView link type' },

  // Upload & Forms
  'phx-drop-target': { type: 'string', description: 'Upload reference' },
  'phx-trigger-action': { type: 'none', description: 'Trigger form submit on patch' },
  'phx-auto-recover': { type: 'event', description: 'Auto-recover form event' },

  // Static tracking
  'phx-track-static': { type: 'none', description: 'Track static assets' },

  // Key filtering
  'phx-key': { type: 'string', description: 'Key name to filter events' },

  // Custom values (dynamic pattern)
  'phx-value-': { type: 'string', description: 'Custom event parameter' },
};

const EVENT_ATTRIBUTE_NAMES = Object.entries(KNOWN_PHOENIX_ATTRS)
  .filter(([, config]) => config.type === 'event')
  .map(([name]) => name);

const EVENT_ATTRIBUTE_NAME_SET = new Set(EVENT_ATTRIBUTE_NAMES);

/**
 * Calculate Levenshtein distance between two strings
 * Used for suggesting corrections for typos
 */
function levenshteinDistance(a: string, b: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Find closest matching attribute name using Levenshtein distance
 */
function findClosestMatch(input: string, candidates: string[]): string | null {
  let minDistance = Infinity;
  let closest: string | null = null;

  for (const candidate of candidates) {
    const distance = levenshteinDistance(input, candidate);
    if (distance < minDistance && distance <= 2) { // Max 2 character difference
      minDistance = distance;
      closest = candidate;
    }
  }

  return closest;
}

/**
 * Parse Phoenix attributes from document text
 */
export function parsePhoenixAttributes(document: TextDocument): PhoenixAttribute[] {
  const text = document.getText();
  const attributes: PhoenixAttribute[] = [];

  // Match: phx-attribute="value" or phx-attribute='value' or phx-attribute={value}
  const regex = /\s(phx-[a-z-]+)\s*=\s*(["'])([^"']*)\2/g;

  let match;
  while ((match = regex.exec(text)) !== null) {
    const attrName = match[1];
    const attrValue = match[3];
    const fullMatchStart = match.index;
    const fullMatchEnd = fullMatchStart + match[0].length;

    if (isInsideDocBlock(text, fullMatchStart)) {
      continue;
    }

    // Calculate position of the value part (for underlining)
    const valueStart = text.indexOf(match[2], fullMatchStart + attrName.length) + 1;
    const valueEnd = valueStart + attrValue.length;

    attributes.push({
      name: attrName,
      value: attrValue,
      range: {
        start: document.positionAt(fullMatchStart),
        end: document.positionAt(fullMatchEnd),
      },
      valueRange: {
        start: document.positionAt(valueStart),
        end: document.positionAt(valueEnd),
      },
    });
  }

  return attributes;
}

function collectEventBindingsFromText(text: string): Set<string> {
  const events = new Set<string>();
  const regex = /\s(phx-[a-z-]+)\s*=\s*(["'])([^"']*)\2/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const attrName = match[1];
    if (!EVENT_ATTRIBUTE_NAME_SET.has(attrName)) {
      continue;
    }
    const value = match[3];
    const staticEvent = getStaticEventName(value);
    if (staticEvent) {
      events.add(staticEvent);
    }
  }
  extractJSPushEvents(text).forEach(eventName => events.add(eventName));
  return events;
}

function isInsideDocBlock(text: string, index: number): boolean {
  const docStart = text.lastIndexOf('@doc', index);
  if (docStart === -1) {
    return false;
  }

  const tripleStart = text.indexOf('"""', docStart);
  if (tripleStart === -1 || tripleStart > index) {
    return false;
  }

  const tripleEnd = text.indexOf('"""', tripleStart + 3);
  if (tripleEnd === -1) {
    return true;
  }

  return index < tripleEnd;
}

/**
 * Check if a value looks like a JS command
 */
function isJSCommand(value: string): boolean {
  return value.trim().startsWith('JS.') || value.includes('|>');
}

/**
 * Check if a value looks like Elixir interpolation
 */
function isInterpolation(value: string): boolean {
  return value.includes('@') || value.includes('#{') || value.includes('}');
}

/**
 * Check if value is empty or placeholder
 */
function isEmpty(value: string): boolean {
  return !value || value.trim() === '';
}

function getStaticEventName(value: string): string | null {
  if (isEmpty(value) || isJSCommand(value) || isInterpolation(value)) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function extractJSPushEvents(text: string): Set<string> {
  const regex = /JS\.push\s*\(\s*["']([^"']+)["']/g;
  const events = new Set<string>();
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const eventName = match[1]?.trim();
    if (eventName) {
      events.add(eventName);
    }
  }
  return events;
}

/**
 * Validate undefined event names
 */
function validateEventBinding(
  attr: PhoenixAttribute,
  eventsRegistry: EventsRegistry,
  filePath: string
): Diagnostic | null {
  const { name, value, valueRange } = attr;

  // Skip validation for empty values
  const staticEvent = getStaticEventName(value);
  if (!staticEvent) {
    return null;
  }

  // Check if event exists in registry
  if (!eventsRegistry.eventExists(staticEvent)) {
    return {
      severity: DiagnosticSeverity.Error,
      range: valueRange,
      message: `Event "${staticEvent}" not found. Define: def handle_event("${staticEvent}", params, socket) in your LiveView module.`,
      source: 'phoenix-lsp',
    };
  }

  return null;
}

/**
 * Validate enum values (e.g., phx-update, phx-link)
 */
function validateEnumValue(
  attr: PhoenixAttribute,
  validValues: string[]
): Diagnostic | null {
  const { value, valueRange } = attr;

  // Skip validation for empty or interpolated values
  if (isEmpty(value) || isInterpolation(value)) {
    return null;
  }

  if (!validValues.includes(value)) {
    return {
      severity: DiagnosticSeverity.Error,
      range: valueRange,
      message: `Invalid value "${value}". Expected one of: ${validValues.join(', ')}`,
      source: 'phoenix-lsp',
    };
  }

  return null;
}

/**
 * Validate debounce value (number or "blur")
 */
function validateDebounceValue(attr: PhoenixAttribute): Diagnostic | null {
  const { value, valueRange } = attr;

  // Skip validation for empty or interpolated values
  if (isEmpty(value) || isInterpolation(value)) {
    return null;
  }

  // Valid: number or "blur"
  if (value !== 'blur' && !/^\d+$/.test(value)) {
    return {
      severity: DiagnosticSeverity.Warning,
      range: valueRange,
      message: `Expected number (milliseconds) or "blur", got "${value}"`,
      source: 'phoenix-lsp',
    };
  }

  return null;
}

/**
 * Validate numeric value
 */
function validateNumericValue(attr: PhoenixAttribute): Diagnostic | null {
  const { value, valueRange } = attr;

  // Skip validation for empty or interpolated values
  if (isEmpty(value) || isInterpolation(value)) {
    return null;
  }

  if (!/^\d+$/.test(value)) {
    return {
      severity: DiagnosticSeverity.Warning,
      range: valueRange,
      message: `Expected number (milliseconds), got "${value}"`,
      source: 'phoenix-lsp',
    };
  }

  return null;
}

/**
 * Validate unknown Phoenix attributes (detect typos)
 */
function validateKnownAttribute(attr: PhoenixAttribute): Diagnostic | null {
  const { name, range } = attr;

  // Check if it's a known attribute
  const knownAttrs = Object.keys(KNOWN_PHOENIX_ATTRS);

  // Check exact match
  if (knownAttrs.includes(name)) {
    return null;
  }

  // Check if it's a phx-value-* variant (dynamic)
  if (name.startsWith('phx-value-')) {
    return null;
  }

  // Find closest match for typo suggestion
  const suggestion = findClosestMatch(name, knownAttrs);

  const message = suggestion
    ? `Unknown Phoenix attribute "${name}". Did you mean "${suggestion}"?`
    : `Unknown Phoenix attribute "${name}". Check for typos.`;

  return {
    severity: DiagnosticSeverity.Error,
    range: range,
    message,
    source: 'phoenix-lsp',
  };
}

/**
 * Main diagnostic validation function
 */
export function validatePhoenixAttributes(
  document: TextDocument,
  eventsRegistry: EventsRegistry,
  filePath: string
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const attributes = parsePhoenixAttributes(document);
  const usedEvents = new Set<string>();

  for (const attr of attributes) {
    const attrConfig = KNOWN_PHOENIX_ATTRS[attr.name];

    // First check: Unknown attribute (typo detection)
    if (!attrConfig && !attr.name.startsWith('phx-value-')) {
      const diagnostic = validateKnownAttribute(attr);
      if (diagnostic) {
        diagnostics.push(diagnostic);
      }
      continue; // Skip other validations for unknown attributes
    }

    // Skip if no config (shouldn't happen after above check, but safety)
    if (!attrConfig) {
      continue;
    }

    // Second check: Event binding validation
    if (attrConfig.type === 'event') {
      const staticEvent = getStaticEventName(attr.value);
      if (staticEvent) {
        usedEvents.add(staticEvent);
      }
      const diagnostic = validateEventBinding(attr, eventsRegistry, filePath);
      if (diagnostic) {
        diagnostics.push(diagnostic);
      }
    }

    // Third check: Enum value validation
    if (attrConfig.type === 'enum' && attrConfig.values) {
      const diagnostic = validateEnumValue(attr, attrConfig.values);
      if (diagnostic) {
        diagnostics.push(diagnostic);
      }
    }

    // Fourth check: Debounce value validation
    if (attrConfig.type === 'debounce') {
      const diagnostic = validateDebounceValue(attr);
      if (diagnostic) {
        diagnostics.push(diagnostic);
      }
    }

    // Fifth check: Numeric value validation
    if (attrConfig.type === 'number') {
      const diagnostic = validateNumericValue(attr);
      if (diagnostic) {
        diagnostics.push(diagnostic);
      }
    }
  }

  const jsPushEvents = extractJSPushEvents(document.getText());
  jsPushEvents.forEach(eventName => usedEvents.add(eventName));

  const modulePath = eventsRegistry.findLiveViewModule(filePath);
  if (modulePath) {
    eventsRegistry.updateTemplateEventUsage(filePath, modulePath, usedEvents);
  }

  // Limit to 100 diagnostics per file for performance
  return diagnostics.slice(0, 100);
}

export function getUnusedEventDiagnostics(
  document: TextDocument,
  eventsRegistry: EventsRegistry,
  templatesRegistry: TemplatesRegistry
): Diagnostic[] {
  const uri = document.uri;
  if (!(uri.endsWith('.ex') || uri.endsWith('.exs'))) {
    return [];
  }

  const filePath = path.normalize(uri.replace('file://', ''));
  const events = eventsRegistry
    .getEventsFromFile(filePath)
    .filter(event => event.kind === 'handle_event' && event.nameKind === 'string');

  if (events.length === 0) {
    return [];
  }

  const aggregatedUsage = eventsRegistry.getAggregatedTemplateEvents(filePath);

  let moduleName = templatesRegistry.getModuleNameForFile(filePath);
  if (!moduleName && events.length > 0) {
    moduleName = events[0].moduleName;
  }

  if (moduleName) {
    const templates = templatesRegistry.getTemplatesForModule(moduleName);
    for (const template of templates) {
      try {
        const templateText = fs.readFileSync(template.filePath, 'utf-8');
        const templateEvents = collectEventBindingsFromText(templateText);
        eventsRegistry.updateTemplateEventUsage(template.filePath, filePath, templateEvents);
        templateEvents.forEach(eventName => aggregatedUsage.add(eventName));
      } catch {
        // Ignore unreadable templates
      }
    }
  }

  const moduleEvents = collectEventBindingsFromText(document.getText());
  eventsRegistry.updateTemplateEventUsage(filePath, filePath, moduleEvents);
  moduleEvents.forEach(eventName => aggregatedUsage.add(eventName));

  const unusedEvents = events.filter(event => !aggregatedUsage.has(event.name));
  if (unusedEvents.length === 0) {
    return [];
  }

  const lines = document.getText().split('\n');
  const diagnostics: Diagnostic[] = [];

  for (const event of unusedEvents) {
    const zeroBasedLine = Math.max(0, event.line - 1);
    const lineText = lines[zeroBasedLine] ?? '';
    const tokens = [`"${event.name}"`, `'${event.name}'`, `:${event.name}`];
    let startChar = -1;
    let length = event.name.length;

    for (const token of tokens) {
      const index = lineText.indexOf(token);
      if (index !== -1) {
        startChar = index;
        length = token.length;
        break;
      }
    }

    if (startChar === -1) {
      const handleIdx = lineText.indexOf('handle_event');
      if (handleIdx !== -1) {
        startChar = handleIdx;
        length = 'handle_event'.length;
      } else {
        startChar = 0;
        length = Math.max(event.name.length, lineText.trim().length);
      }
    }

    diagnostics.push({
      severity: DiagnosticSeverity.Hint,
      range: {
        start: { line: zeroBasedLine, character: Math.max(0, startChar) },
        end: { line: zeroBasedLine, character: Math.max(0, startChar + length) },
      },
      message: `Event "${event.name}" is never referenced by this LiveView or its templates.`,
      source: 'phoenix-lsp',
      code: 'unused-event',
    });
  }

  return diagnostics;
}

/**
 * Validate that :for loops have :key attributes for efficient diffing
 */
export function validateForLoopKeys(document: TextDocument): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Match :for attributes on HTML elements and components
  // Pattern: <tag :for={...} or <.component :for={...}
  const forAttrPattern = /:for\s*=\s*\{[^}]+\}/g;

  let match: RegExpExecArray | null;
  while ((match = forAttrPattern.exec(text)) !== null) {
    const forAttrStart = match.index;
    const forAttrEnd = forAttrStart + match[0].length;

    // Find the opening tag that contains this :for
    let tagStart = forAttrStart;
    while (tagStart > 0 && text[tagStart] !== '<') {
      tagStart--;
    }

    // Find the end of the opening tag
    let tagEnd = forAttrEnd;
    let depth = 0;
    while (tagEnd < text.length) {
      const ch = text[tagEnd];
      if (ch === '<') depth++;
      if (ch === '>') {
        if (depth === 0) break;
        depth--;
      }
      tagEnd++;
    }

    const tagContent = text.substring(tagStart, tagEnd + 1);

    // Skip validation for stream iterations (@streams.*)
    // Streams use id={dom_id} for DOM tracking, not :key
    // Stream validation is handled by validateStreams()
    if (/@streams\./.test(tagContent)) {
      continue;
    }

    // Skip validation for component iterations (<.component>)
    // Components manage their own keys internally
    if (/<\.[a-z]/.test(tagContent)) {
      continue;
    }

    // Check if this tag has EITHER id= OR :key= attribute for DOM tracking
    // id= works in all LiveView versions (1.0+)
    // :key= is more efficient but requires LiveView 1.1+
    const hasId = /\sid\s*=\s*\{/.test(tagContent);
    const hasKey = /:key\s*=\s*[{"']/.test(tagContent);

    if (!hasId && !hasKey) {
      // Extract tag name for better error message
      const tagNameMatch = tagContent.match(/<(\.?[a-zA-Z][a-zA-Z0-9._-]*)/);
      const tagName = tagNameMatch ? tagNameMatch[1] : 'element';

      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: {
          start: document.positionAt(forAttrStart),
          end: document.positionAt(forAttrEnd),
        },
        message: `Element "${tagName}" with :for should have DOM tracking. Add id={"item-\#{item.id}"} (LiveView 1.0+) or :key={item.id} (LiveView 1.1+).`,
        source: 'phoenix-lsp',
        code: 'for-missing-key',
      });
    }
  }

  return diagnostics;
}
