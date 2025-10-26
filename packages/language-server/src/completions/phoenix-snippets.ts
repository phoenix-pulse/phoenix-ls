import { CompletionItem, CompletionItemKind, InsertTextFormat, Position, Range, TextEdit } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

/**
 * Phoenix/LiveView-specific snippet completions
 *
 * This provider offers shortcuts for common Phoenix LiveView patterns
 * without requiring user configuration. Works alongside Emmet.
 */

// ============================================================================
// PATTERN DETECTION
// ============================================================================

/**
 * Detects if linePrefix ends with a component shortcut pattern
 * Examples: .live, .modal, .form, .table, .link
 */
function isComponentShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/\.([a-z]+)$/);
  if (!match) return null;

  const componentShortcuts = ['live', 'modal', 'form', 'table', 'link', 'button', 'input'];
  return componentShortcuts.includes(match[1]) ? match[1] : null;
}

/**
 * Detects if linePrefix ends with a HEEx shortcut pattern
 * Examples: :for, :if, :unless, :let, or just :
 */
function isHEExShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/:([a-z]*)$/);
  if (!match) return null;

  const heexShortcuts = ['for', 'if', 'unless', 'let'];

  // If specific shortcut typed, return it if valid
  if (match[1] && heexShortcuts.includes(match[1])) {
    return match[1];
  }

  // If just ":" or partial match, return empty string to show all
  if (match[1].length === 0 || heexShortcuts.some(s => s.startsWith(match[1]))) {
    return ''; // Empty string signals "show all HEEx shortcuts"
  }

  return null;
}

/**
 * Detects if linePrefix ends with a Phoenix pattern shortcut
 * Examples: form.phx, link.phx, btn.phx, input.phx, div.loading, div.error
 */
function isPhoenixPattern(linePrefix: string): string | null {
  const match = linePrefix.match(/([a-z]+)\.(phx|loading|error)$/);
  return match ? `${match[1]}.${match[2]}` : null;
}

/**
 * Detects if linePrefix ends with an event shortcut
 * Examples: @click, @submit, @change, @click.target, @click.debounce, or just @
 */
function isEventShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/@([a-z]*)(?:\.([a-z]*))?$/);
  if (!match) return null;

  const events = ['click', 'submit', 'change', 'blur', 'focus', 'keydown', 'keyup', 'input'];
  const modifiers = ['target', 'debounce', 'throttle'];

  // If specific event + modifier typed
  if (match[1] && match[2]) {
    if (events.includes(match[1]) && modifiers.includes(match[2])) {
      return `${match[1]}.${match[2]}`;
    }
    return null;
  }

  // If specific event typed (no modifier)
  if (match[1] && events.includes(match[1])) {
    return match[1];
  }

  // If just "@" (no letters after), show all events
  // Don't match partial prefixes to avoid blocking assigns like @current_user, @state
  if (match[1].length === 0) {
    return ''; // Empty string signals "show all event shortcuts"
  }

  return null;
}

/**
 * Detects if linePrefix ends with a form shortcut
 * Examples: input.text, input.email, select.phx, checkbox.phx
 */
function isFormShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/(input|select|checkbox|textarea)\.(text|email|password|number|phx)$/);
  return match ? `${match[1]}.${match[2]}` : null;
}

/**
 * Detects if linePrefix ends with a route shortcut
 * Examples: link.nav, link.patch, a.nav
 */
function isRouteShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/(link|a)\.(nav|patch|href)$/);
  return match ? `${match[1]}.${match[2]}` : null;
}

/**
 * Detects if linePrefix ends with an asset shortcut
 * Examples: img.static, link.css, script.js
 */
function isAssetShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/(img|link|script)\.(static|css|js)$/);
  return match ? `${match[1]}.${match[2]}` : null;
}

/**
 * Detects if linePrefix ends with a layout shortcut
 * Examples: .hero, .card, .grid
 */
function isLayoutShortcut(linePrefix: string): string | null {
  const match = linePrefix.match(/\.([a-z]+)$/);
  if (!match) return null;

  const layouts = ['hero', 'card', 'grid', 'container', 'section'];
  return layouts.includes(match[1]) ? match[1] : null;
}

/**
 * Detects stream shortcut
 */
function isStreamShortcut(linePrefix: string): boolean {
  return linePrefix.endsWith('stream');
}

// ============================================================================
// SNIPPET DEFINITIONS
// ============================================================================

/**
 * Component shortcuts (triggered by .live, .modal, etc.)
 */
const COMPONENT_SNIPPETS: Record<string, string> = {
  live: `<.live_component module={\${1:Module}} id="\${2:id}" />`,

  modal: `<.modal id="\${1:modal-id}">
  <:title>\${2:Modal Title}</:title>
  \${3:Modal content}
</.modal>`,

  form: `<.simple_form for={@form} phx-submit="\${1:save}">
  <.input field={@form[:\${2:field}]} label="\${3:Label}" />
  <:actions>
    <.button>Save</.button>
  </:actions>
</.simple_form>`,

  table: `<.table rows={@\${1:items}}>
  <:col :let={item} label="\${2:Label}">{item.\${3:field}}</:col>
</.table>`,

  link: `<.link navigate={~p"/\${1:path}"}>\${2:Link text}</.link>`,

  button: `<.button phx-click="\${1:action}">\${2:Button text}</.button>`,

  input: `<.input field={@form[:\${1:field}]} label="\${2:Label}" />`,
};

/**
 * HEEx template shortcuts (triggered by :for, :if, etc.)
 */
const HEEX_SNIPPETS: Record<string, string> = {
  for: `<div :for={item <- @\${1:items}}>
  {item.\${2:field}}
</div>`,

  if: `<div :if={@\${1:condition}}>
  \${2:Content}
</div>`,

  unless: `<div :unless={@\${1:condition}}>
  \${2:Content}
</div>`,

  let: `<:\${1:slot_name} :let={\${2:var}}>
  \${3:Content}
</:\${1:slot_name}>`,
};

/**
 * Phoenix pattern shortcuts (triggered by form.phx, link.phx, etc.)
 */
const PHOENIX_PATTERN_SNIPPETS: Record<string, string> = {
  'form.phx': `<form phx-submit="\${1:save}">
  <input type="text" name="\${2:field}" value={@\${2:field}} />
  <button type="submit">Submit</button>
</form>`,

  'link.phx': `<a href="#" phx-click="\${1:action}">\${2:Link text}</a>`,

  'btn.phx': `<button type="button" phx-click="\${1:action}">\${2:Button text}</button>`,

  'button.phx': `<button type="button" phx-click="\${1:action}">\${2:Button text}</button>`,

  'input.phx': `<input type="text" name="\${1:field}" value={@\${1:field}} phx-blur="validate" />`,

  'div.loading': `<div :if={@loading} class="spinner">Loading...</div>`,

  'div.error': `<div :if={@error} class="alert alert-danger">{@error}</div>`,
};

/**
 * Stream shortcut
 */
const STREAM_SNIPPET = `<div id="{\${1:stream_name}-stream}" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.\${1:stream_name}} id={dom_id}>
    {item.\${2:field}}
  </div>
</div>`;

/**
 * Event shortcuts (triggered by @click, @submit, etc.)
 */
const EVENT_SNIPPETS: Record<string, string> = {
  click: `phx-click="\${1:action}"`,
  submit: `phx-submit="\${1:action}"`,
  change: `phx-change="\${1:action}"`,
  blur: `phx-blur="\${1:action}"`,
  focus: `phx-focus="\${1:action}"`,
  keydown: `phx-keydown="\${1:action}"`,
  keyup: `phx-keyup="\${1:action}"`,
  input: `phx-input="\${1:action}"`,

  // With modifiers
  'click.target': `phx-click="\${1:action}" phx-target={@myself}`,
  'click.debounce': `phx-click="\${1:action}" phx-debounce="\${2:300}"`,
  'click.throttle': `phx-click="\${1:action}" phx-throttle="\${2:1000}"`,
  'submit.target': `phx-submit="\${1:action}" phx-target={@myself}`,
  'change.debounce': `phx-change="\${1:action}" phx-debounce="\${2:300}"`,
  'blur.debounce': `phx-blur="\${1:action}" phx-debounce="\${2:300}"`,
};

/**
 * Form shortcuts (triggered by input.text, select.phx, etc.)
 */
const FORM_SNIPPETS: Record<string, string> = {
  'input.text': `<input type="text" name="\${1:field}" value={@\${1:field}} phx-blur="validate" />`,

  'input.email': `<input type="email" name="email" value={@email} required phx-blur="validate" />`,

  'input.password': `<input type="password" name="password" required phx-blur="validate" />`,

  'input.number': `<input type="number" name="\${1:field}" value={@\${1:field}} phx-blur="validate" />`,

  'select.phx': `<select name="\${1:field}" phx-change="\${2:update}">
  <option :for={opt <- @\${3:options}} value={opt.value}>{opt.label}</option>
</select>`,

  'checkbox.phx': `<input type="checkbox" name="\${1:field}" checked={@\${1:field}} phx-click="\${2:toggle}" />`,

  'textarea.phx': `<textarea name="\${1:field}" phx-blur="validate">{@\${1:field}}</textarea>`,
};

/**
 * Route shortcuts (triggered by link.nav, a.nav, etc.)
 */
const ROUTE_SNIPPETS: Record<string, string> = {
  'link.nav': `<.link navigate={~p"/\${1:path}"}>\${2:Link text}</.link>`,
  'link.patch': `<.link patch={~p"/\${1:path}"}>\${2:Link text}</.link>`,
  'link.href': `<.link href={~p"/\${1:path}"}>\${2:Link text}</.link>`,
  'a.nav': `<a href={~p"/\${1:path}"}>\${2:Link text}</a>`,
  'a.patch': `<a href={~p"/\${1:path}"} data-phx-link="patch" data-phx-link-state="push">\${2:Link text}</a>`,
  'a.href': `<a href={~p"/\${1:path}"}>\${2:Link text}</a>`,
};

/**
 * Asset shortcuts (triggered by img.static, link.css, etc.)
 */
const ASSET_SNIPPETS: Record<string, string> = {
  'img.static': `<img src={~p"/images/\${1:filename}"} alt="\${2:Alt text}" />`,
  'link.css': `<link rel="stylesheet" href={~p"/assets/\${1:filename}.css"} />`,
  'script.js': `<script src={~p"/assets/\${1:filename}.js"}></script>`,
};

/**
 * Layout shortcuts (triggered by .hero, .card, etc.)
 */
const LAYOUT_SNIPPETS: Record<string, string> = {
  hero: `<div class="hero">
  <h1>\${1:Hero Title}</h1>
  <p>\${2:Hero description}</p>
</div>`,

  card: `<div class="card">
  <div class="card-header">\${1:Header}</div>
  <div class="card-body">\${2:Content}</div>
</div>`,

  grid: `<div class="grid grid-cols-\${1:3} gap-4">
  \${2:Grid items}
</div>`,

  container: `<div class="container mx-auto px-4">
  \${1:Content}
</div>`,

  section: `<section class="\${1:section-class}">
  <h2>\${2:Section Title}</h2>
  \${3:Section content}
</section>`,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Creates a completion item from snippet text
 */
function createSnippetCompletion(
  label: string,
  snippet: string,
  detail: string,
  documentation: string,
  document: TextDocument,
  position: Position,
  triggerLength: number,
  sortPriority: number = 0,
  kind: CompletionItemKind = CompletionItemKind.Snippet
): CompletionItem {
  // Calculate range to replace (from position - triggerLength to position)
  const offset = document.offsetAt(position);
  const startOffset = offset - triggerLength;
  const startPosition = document.positionAt(startOffset);
  const range = Range.create(startPosition, position);

  return {
    label,
    kind, // Use parameter instead of hardcoded Snippet
    detail,
    documentation,
    textEdit: TextEdit.replace(range, snippet),
    insertTextFormat: InsertTextFormat.Snippet,
    sortText: `!00${sortPriority.toString().padStart(3, '0')}`,
    preselect: sortPriority === 0, // Preselect highest priority
  };
}

// ============================================================================
// MAIN EXPORT
// ============================================================================

/**
 * Get Phoenix/LiveView-specific snippet completions
 *
 * @param linePrefix - Text from start of line to cursor position
 * @param document - Text document
 * @param position - Cursor position
 * @returns Array of completion items (empty if no match)
 */
export function getPhoenixSnippetCompletions(
  linePrefix: string,
  document: TextDocument,
  position: Position
): CompletionItem[] {
  // Check each pattern type and return appropriate completions

  // 1. Component shortcuts (.live, .modal, etc.)
  const componentShortcut = isComponentShortcut(linePrefix);
  if (componentShortcut && componentShortcut in COMPONENT_SNIPPETS) {
    const triggerText = `.${componentShortcut}`;
    return [
      createSnippetCompletion(
        triggerText,
        COMPONENT_SNIPPETS[componentShortcut],
        `Phoenix component: <.${componentShortcut}>`,
        `Insert a ${componentShortcut} component with common attributes`,
        document,
        position,
        triggerText.length,
        0
      ),
    ];
  }

  // 2. HEEx shortcuts (:for, :if, etc.)
  const heexShortcut = isHEExShortcut(linePrefix);
  if (heexShortcut !== null) {
    // If empty string, show all HEEx shortcuts
    if (heexShortcut === '') {
      const completions: CompletionItem[] = [];
      const heexKeys = Object.keys(HEEX_SNIPPETS);
      heexKeys.forEach((key, index) => {
        const triggerText = `:${key}`;
        // Calculate trigger length: just ":" if they only typed ":"
        const match = linePrefix.match(/:([a-z]*)$/);
        const typedLength = match ? match[0].length : 1;
        completions.push(
          createSnippetCompletion(
            triggerText,
            HEEX_SNIPPETS[key],
            `HEEx attribute: :${key}`,
            `Insert a :${key} template directive`,
            document,
            position,
            typedLength,
            index
          )
        );
      });
      return completions;
    }

    // If specific shortcut, return it
    if (heexShortcut in HEEX_SNIPPETS) {
      const triggerText = `:${heexShortcut}`;
      return [
        createSnippetCompletion(
          triggerText,
          HEEX_SNIPPETS[heexShortcut],
          `HEEx attribute: :${heexShortcut}`,
          `Insert a :${heexShortcut} template directive`,
          document,
          position,
          triggerText.length,
          0
        ),
      ];
    }
  }

  // 3. Stream shortcut
  if (isStreamShortcut(linePrefix)) {
    const triggerText = 'stream';
    return [
      createSnippetCompletion(
        triggerText,
        STREAM_SNIPPET,
        'Phoenix Stream iteration',
        'Insert a LiveView stream iteration pattern',
        document,
        position,
        triggerText.length,
        0
      ),
    ];
  }

  // 4. Phoenix patterns (form.phx, link.phx, etc.)
  const phoenixPattern = isPhoenixPattern(linePrefix);
  if (phoenixPattern && phoenixPattern in PHOENIX_PATTERN_SNIPPETS) {
    return [
      createSnippetCompletion(
        phoenixPattern,
        PHOENIX_PATTERN_SNIPPETS[phoenixPattern],
        `Phoenix pattern: ${phoenixPattern}`,
        `Insert a ${phoenixPattern} pattern`,
        document,
        position,
        phoenixPattern.length,
        0
      ),
    ];
  }

  // 5. Event shortcuts (@click, @submit, etc.)
  const eventShortcut = isEventShortcut(linePrefix);
  if (eventShortcut !== null) {
    // If empty string, show all event shortcuts (base events only, not modifiers)
    if (eventShortcut === '') {
      const completions: CompletionItem[] = [];
      const baseEvents = ['click', 'submit', 'change', 'blur', 'focus', 'keydown', 'keyup', 'input'];
      // Calculate trigger length: what they typed starting from "@"
      const match = linePrefix.match(/@([a-z]*)(?:\.([a-z]*))?$/);
      const typedLength = match ? match[0].length : 1;

      baseEvents.forEach((event, index) => {
        const triggerText = `@${event}`;
        if (event in EVENT_SNIPPETS) {
          completions.push(
            createSnippetCompletion(
              triggerText,
              EVENT_SNIPPETS[event],
              `Phoenix event: phx-${event}`,
              `Insert a phx-${event} event binding`,
              document,
              position,
              typedLength,
              index,
              CompletionItemKind.Event // Event icon for visual distinction
            )
          );
        }
      });
      return completions;
    }

    // If specific event, return it
    if (eventShortcut in EVENT_SNIPPETS) {
      const triggerText = `@${eventShortcut}`;
      return [
        createSnippetCompletion(
          triggerText,
          EVENT_SNIPPETS[eventShortcut],
          `Phoenix event: phx-${eventShortcut.split('.')[0]}`,
          `Insert a phx-${eventShortcut.split('.')[0]} event binding`,
          document,
          position,
          triggerText.length,
          0,
          CompletionItemKind.Event // Event icon for visual distinction
        ),
      ];
    }
  }

  // 6. Form shortcuts (input.text, select.phx, etc.)
  const formShortcut = isFormShortcut(linePrefix);
  if (formShortcut && formShortcut in FORM_SNIPPETS) {
    return [
      createSnippetCompletion(
        formShortcut,
        FORM_SNIPPETS[formShortcut],
        `Form element: ${formShortcut}`,
        `Insert a ${formShortcut} form element with Phoenix bindings`,
        document,
        position,
        formShortcut.length,
        0
      ),
    ];
  }

  // 7. Route shortcuts (link.nav, a.nav, etc.)
  const routeShortcut = isRouteShortcut(linePrefix);
  if (routeShortcut && routeShortcut in ROUTE_SNIPPETS) {
    return [
      createSnippetCompletion(
        routeShortcut,
        ROUTE_SNIPPETS[routeShortcut],
        `Route link: ${routeShortcut}`,
        `Insert a ${routeShortcut} with verified route`,
        document,
        position,
        routeShortcut.length,
        0
      ),
    ];
  }

  // 8. Asset shortcuts (img.static, link.css, etc.)
  const assetShortcut = isAssetShortcut(linePrefix);
  if (assetShortcut && assetShortcut in ASSET_SNIPPETS) {
    return [
      createSnippetCompletion(
        assetShortcut,
        ASSET_SNIPPETS[assetShortcut],
        `Asset: ${assetShortcut}`,
        `Insert a ${assetShortcut} with verified route`,
        document,
        position,
        assetShortcut.length,
        0
      ),
    ];
  }

  // 9. Layout shortcuts (.hero, .card, etc.)
  const layoutShortcut = isLayoutShortcut(linePrefix);
  if (layoutShortcut && layoutShortcut in LAYOUT_SNIPPETS) {
    const triggerText = `.${layoutShortcut}`;
    return [
      createSnippetCompletion(
        triggerText,
        LAYOUT_SNIPPETS[layoutShortcut],
        `Layout: ${layoutShortcut}`,
        `Insert a ${layoutShortcut} layout pattern`,
        document,
        position,
        triggerText.length,
        0
      ),
    ];
  }

  // No match - return empty array
  return [];
}
