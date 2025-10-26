/**
 * Complete HTML5 attribute mappings
 * Source: MDN Web Docs + HTML Living Standard
 *
 * This file provides context-aware HTML attribute completions.
 * Shows element-specific attributes + global attributes + ARIA attributes.
 */

export interface AttributeData {
  readonly name: string;
  readonly values: readonly string[];
  readonly doc: string;
  readonly boolean?: boolean;
  readonly snippet?: string;
}

// ===== GLOBAL ATTRIBUTES (work on all elements) =====
export const GLOBAL_ATTRS: readonly AttributeData[] = [
  // Identity & Classes
  { name: 'id', values: [], doc: 'Unique element identifier' },
  { name: 'class', values: [], doc: 'CSS classes (space-separated)' },
  { name: 'style', values: [], doc: 'Inline CSS styles' },

  // Internationalization
  { name: 'lang', values: ['en', 'es', 'fr', 'de', 'ja', 'zh', 'pt', 'ru', 'ar'], doc: 'Language code (ISO 639-1)' },
  { name: 'dir', values: ['ltr', 'rtl', 'auto'], doc: 'Text direction' },
  { name: 'translate', values: ['yes', 'no'], doc: 'Translation hint' },

  // Accessibility
  { name: 'title', values: [], doc: 'Advisory information (tooltip)' },
  { name: 'tabindex', values: [], doc: 'Tab order (-1, 0, or positive integer)' },
  { name: 'accesskey', values: [], doc: 'Keyboard shortcut' },
  { name: 'hidden', values: [], doc: 'Hidden element', boolean: true },

  // Behavior
  { name: 'contenteditable', values: ['true', 'false'], doc: 'Editable content' },
  { name: 'draggable', values: ['true', 'false'], doc: 'Draggable element' },
  { name: 'spellcheck', values: ['true', 'false'], doc: 'Spell checking' },
  { name: 'autocapitalize', values: ['off', 'none', 'on', 'sentences', 'words', 'characters'], doc: 'Auto-capitalization behavior' },

  // Custom data
  { name: 'data-', values: [], doc: 'Custom data attribute', snippet: 'data-${1:name}="${2:value}"' },
] as const;

// ===== ARIA ATTRIBUTES =====
export const ARIA_ATTRS: readonly AttributeData[] = [
  // Labels & Descriptions
  { name: 'role', values: ['button', 'link', 'navigation', 'main', 'banner', 'contentinfo', 'search', 'form', 'region', 'article', 'complementary', 'menu', 'menuitem', 'tab', 'tabpanel', 'dialog', 'alert', 'status'], doc: 'ARIA role' },
  { name: 'aria-label', values: [], doc: 'Accessible label' },
  { name: 'aria-labelledby', values: [], doc: 'ID reference to labeling element(s)' },
  { name: 'aria-describedby', values: [], doc: 'ID reference to describing element(s)' },

  // States
  { name: 'aria-hidden', values: ['true', 'false'], doc: 'Hidden from assistive technologies' },
  { name: 'aria-expanded', values: ['true', 'false'], doc: 'Element is expanded' },
  { name: 'aria-disabled', values: ['true', 'false'], doc: 'Element is disabled' },
  { name: 'aria-checked', values: ['true', 'false', 'mixed'], doc: 'Checkbox/radio state' },
  { name: 'aria-selected', values: ['true', 'false'], doc: 'Selected state' },
  { name: 'aria-pressed', values: ['true', 'false', 'mixed'], doc: 'Toggle button state' },
  { name: 'aria-current', values: ['page', 'step', 'location', 'date', 'time', 'true', 'false'], doc: 'Current item indicator' },
  { name: 'aria-invalid', values: ['true', 'false', 'grammar', 'spelling'], doc: 'Validation state' },
  { name: 'aria-required', values: ['true', 'false'], doc: 'Required field' },
  { name: 'aria-readonly', values: ['true', 'false'], doc: 'Read-only field' },

  // Live regions
  { name: 'aria-live', values: ['off', 'polite', 'assertive'], doc: 'Live region politeness' },
  { name: 'aria-atomic', values: ['true', 'false'], doc: 'Announce entire region on change' },
  { name: 'aria-relevant', values: ['additions', 'removals', 'text', 'all'], doc: 'What changes to announce' },

  // Relationships
  { name: 'aria-controls', values: [], doc: 'IDs of controlled elements' },
  { name: 'aria-owns', values: [], doc: 'IDs of owned elements' },
  { name: 'aria-flowto', values: [], doc: 'ID of next element in reading order' },

  // Values
  { name: 'aria-valuemin', values: [], doc: 'Minimum value' },
  { name: 'aria-valuemax', values: [], doc: 'Maximum value' },
  { name: 'aria-valuenow', values: [], doc: 'Current value' },
  { name: 'aria-valuetext', values: [], doc: 'Human-readable value' },
] as const;

// ===== ELEMENT-SPECIFIC ATTRIBUTES =====
export const ELEMENT_ATTRS = {
  // Images
  img: [
    { name: 'src', values: [], doc: 'Image URL (required)' },
    { name: 'alt', values: [], doc: 'Alternative text (required for accessibility)' },
    { name: 'width', values: [], doc: 'Image width in pixels' },
    { name: 'height', values: [], doc: 'Image height in pixels' },
    { name: 'loading', values: ['lazy', 'eager'], doc: 'Loading strategy (lazy = load when visible)' },
    { name: 'decoding', values: ['async', 'sync', 'auto'], doc: 'Image decode strategy' },
    { name: 'srcset', values: [], doc: 'Responsive image sources (e.g., "img.jpg 1x, img@2x.jpg 2x")' },
    { name: 'sizes', values: [], doc: 'Image sizes for responsive images (e.g., "(max-width: 600px) 100vw, 50vw")' },
    { name: 'crossorigin', values: ['anonymous', 'use-credentials'], doc: 'CORS mode for cross-origin images' },
    { name: 'fetchpriority', values: ['high', 'low', 'auto'], doc: 'Fetch priority hint' },
    { name: 'ismap', values: [], doc: 'Server-side image map', boolean: true },
    { name: 'usemap', values: [], doc: 'Client-side image map reference (#map-name)' },
  ],

  // Links
  a: [
    { name: 'href', values: [], doc: 'Link destination URL' },
    { name: 'target', values: ['_blank', '_self', '_parent', '_top'], doc: 'Where to open the link' },
    { name: 'rel', values: ['noopener', 'noreferrer', 'nofollow', 'external', 'alternate', 'author', 'bookmark', 'help', 'license', 'next', 'prev', 'search', 'tag'], doc: 'Link relationship' },
    { name: 'download', values: [], doc: 'Download filename (prompts download instead of navigation)' },
    { name: 'hreflang', values: [], doc: 'Language of linked resource (e.g., "en", "es")' },
    { name: 'type', values: [], doc: 'MIME type of linked resource' },
    { name: 'ping', values: [], doc: 'Space-separated URLs to ping when link clicked' },
    { name: 'referrerpolicy', values: ['no-referrer', 'no-referrer-when-downgrade', 'origin', 'origin-when-cross-origin', 'same-origin', 'strict-origin', 'strict-origin-when-cross-origin', 'unsafe-url'], doc: 'Referrer policy for link navigation' },
  ],

  // Forms
  form: [
    { name: 'action', values: [], doc: 'URL to submit form data' },
    { name: 'method', values: ['get', 'post'], doc: 'HTTP method for form submission' },
    { name: 'enctype', values: ['application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain'], doc: 'Form data encoding type' },
    { name: 'target', values: ['_blank', '_self', '_parent', '_top'], doc: 'Where to display form response' },
    { name: 'novalidate', values: [], doc: 'Skip HTML5 validation', boolean: true },
    { name: 'autocomplete', values: ['on', 'off'], doc: 'Form autocomplete behavior' },
    { name: 'name', values: [], doc: 'Form name (for document.forms access)' },
    { name: 'accept-charset', values: ['UTF-8', 'ISO-8859-1'], doc: 'Character encodings for form submission' },
  ],

  // Input (comprehensive!)
  input: [
    { name: 'type', values: ['text', 'email', 'password', 'number', 'tel', 'url', 'search', 'date', 'datetime-local', 'time', 'month', 'week', 'checkbox', 'radio', 'file', 'submit', 'button', 'reset', 'hidden', 'range', 'color'], doc: 'Input control type' },
    { name: 'name', values: [], doc: 'Form control name' },
    { name: 'value', values: [], doc: 'Current value' },
    { name: 'placeholder', values: [], doc: 'Placeholder text (shown when empty)' },
    { name: 'required', values: [], doc: 'Required field', boolean: true },
    { name: 'disabled', values: [], doc: 'Disabled field', boolean: true },
    { name: 'readonly', values: [], doc: 'Read-only field', boolean: true },
    { name: 'checked', values: [], doc: 'Checked state (for checkbox/radio)', boolean: true },
    { name: 'autofocus', values: [], doc: 'Auto-focus on page load', boolean: true },
    { name: 'autocomplete', values: ['on', 'off', 'name', 'email', 'username', 'new-password', 'current-password', 'tel', 'url', 'street-address', 'postal-code', 'cc-number'], doc: 'Autocomplete hint' },
    { name: 'pattern', values: [], doc: 'Validation regex pattern' },
    { name: 'min', values: [], doc: 'Minimum value (for number/date/time)' },
    { name: 'max', values: [], doc: 'Maximum value (for number/date/time)' },
    { name: 'step', values: [], doc: 'Value increment step (for number/range)' },
    { name: 'maxlength', values: [], doc: 'Maximum character length' },
    { name: 'minlength', values: [], doc: 'Minimum character length' },
    { name: 'size', values: [], doc: 'Visible width in characters' },
    { name: 'multiple', values: [], doc: 'Allow multiple values (for file/email)', boolean: true },
    { name: 'accept', values: ['image/*', 'video/*', 'audio/*', '.jpg,.png,.gif', '.pdf', '.doc,.docx'], doc: 'Accepted file types (for type="file")' },
    { name: 'capture', values: ['user', 'environment'], doc: 'Camera capture mode (for type="file")' },
    { name: 'list', values: [], doc: 'Datalist ID reference for autocomplete options' },
    { name: 'form', values: [], doc: 'Associated form ID (overrides containing form)' },
    { name: 'formaction', values: [], doc: 'Override form action URL' },
    { name: 'formmethod', values: ['get', 'post'], doc: 'Override form method' },
    { name: 'formnovalidate', values: [], doc: 'Skip form validation', boolean: true },
  ],

  // Button
  button: [
    { name: 'type', values: ['submit', 'reset', 'button'], doc: 'Button type (submit = submit form, button = no default action)' },
    { name: 'name', values: [], doc: 'Button name (sent with form data)' },
    { name: 'value', values: [], doc: 'Button value (sent with form data)' },
    { name: 'disabled', values: [], doc: 'Disabled button', boolean: true },
    { name: 'autofocus', values: [], doc: 'Auto-focus on page load', boolean: true },
    { name: 'form', values: [], doc: 'Associated form ID' },
    { name: 'formaction', values: [], doc: 'Override form action URL' },
    { name: 'formmethod', values: ['get', 'post'], doc: 'Override form method' },
    { name: 'formnovalidate', values: [], doc: 'Skip form validation', boolean: true },
  ],

  // Textarea
  textarea: [
    { name: 'name', values: [], doc: 'Control name' },
    { name: 'rows', values: [], doc: 'Visible rows (height)' },
    { name: 'cols', values: [], doc: 'Visible columns (width)' },
    { name: 'placeholder', values: [], doc: 'Placeholder text' },
    { name: 'required', values: [], doc: 'Required field', boolean: true },
    { name: 'disabled', values: [], doc: 'Disabled field', boolean: true },
    { name: 'readonly', values: [], doc: 'Read-only field', boolean: true },
    { name: 'maxlength', values: [], doc: 'Maximum character length' },
    { name: 'minlength', values: [], doc: 'Minimum character length' },
    { name: 'autocomplete', values: ['on', 'off'], doc: 'Autocomplete behavior' },
    { name: 'autofocus', values: [], doc: 'Auto-focus on page load', boolean: true },
    { name: 'wrap', values: ['soft', 'hard'], doc: 'Text wrapping mode (soft = visual only, hard = insert line breaks)' },
  ],

  // Select
  select: [
    { name: 'name', values: [], doc: 'Control name' },
    { name: 'multiple', values: [], doc: 'Allow multiple selection', boolean: true },
    { name: 'size', values: [], doc: 'Number of visible options' },
    { name: 'required', values: [], doc: 'Required field', boolean: true },
    { name: 'disabled', values: [], doc: 'Disabled field', boolean: true },
    { name: 'autofocus', values: [], doc: 'Auto-focus on page load', boolean: true },
    { name: 'autocomplete', values: ['on', 'off'], doc: 'Autocomplete behavior' },
  ],

  // Option
  option: [
    { name: 'value', values: [], doc: 'Option value (sent with form)' },
    { name: 'selected', values: [], doc: 'Selected by default', boolean: true },
    { name: 'disabled', values: [], doc: 'Disabled option', boolean: true },
    { name: 'label', values: [], doc: 'Option label (alternative to text content)' },
  ],

  // Label
  label: [
    { name: 'for', values: [], doc: 'Associated form control ID' },
  ],

  // Media - Video
  video: [
    { name: 'src', values: [], doc: 'Video source URL' },
    { name: 'poster', values: [], doc: 'Poster image URL (shown before video loads)' },
    { name: 'controls', values: [], doc: 'Show playback controls', boolean: true },
    { name: 'autoplay', values: [], doc: 'Auto-play video on load', boolean: true },
    { name: 'loop', values: [], doc: 'Loop playback', boolean: true },
    { name: 'muted', values: [], doc: 'Muted audio by default', boolean: true },
    { name: 'preload', values: ['none', 'metadata', 'auto'], doc: 'Preload strategy (none = no preload, metadata = only metadata, auto = full video)' },
    { name: 'width', values: [], doc: 'Video width in pixels' },
    { name: 'height', values: [], doc: 'Video height in pixels' },
    { name: 'crossorigin', values: ['anonymous', 'use-credentials'], doc: 'CORS mode for cross-origin video' },
    { name: 'playsinline', values: [], doc: 'Play inline on mobile (not fullscreen)', boolean: true },
  ],

  // Media - Audio
  audio: [
    { name: 'src', values: [], doc: 'Audio source URL' },
    { name: 'controls', values: [], doc: 'Show playback controls', boolean: true },
    { name: 'autoplay', values: [], doc: 'Auto-play audio on load', boolean: true },
    { name: 'loop', values: [], doc: 'Loop playback', boolean: true },
    { name: 'muted', values: [], doc: 'Muted audio by default', boolean: true },
    { name: 'preload', values: ['none', 'metadata', 'auto'], doc: 'Preload strategy' },
    { name: 'crossorigin', values: ['anonymous', 'use-credentials'], doc: 'CORS mode for cross-origin audio' },
  ],

  // Source (for video/audio)
  source: [
    { name: 'src', values: [], doc: 'Media source URL' },
    { name: 'type', values: ['video/mp4', 'video/webm', 'video/ogg', 'audio/mpeg', 'audio/ogg', 'audio/wav'], doc: 'MIME type of media source' },
    { name: 'media', values: [], doc: 'Media query for source selection' },
    { name: 'sizes', values: [], doc: 'Image sizes (for picture element)' },
    { name: 'srcset', values: [], doc: 'Image source set (for picture element)' },
  ],

  // Track (for video/audio)
  track: [
    { name: 'src', values: [], doc: 'Track file URL (WebVTT format)' },
    { name: 'kind', values: ['subtitles', 'captions', 'descriptions', 'chapters', 'metadata'], doc: 'Track type' },
    { name: 'srclang', values: ['en', 'es', 'fr', 'de', 'ja', 'zh'], doc: 'Track language code' },
    { name: 'label', values: [], doc: 'Track label (user-visible)' },
    { name: 'default', values: [], doc: 'Default track', boolean: true },
  ],

  // Tables
  td: [
    { name: 'colspan', values: [], doc: 'Number of columns to span' },
    { name: 'rowspan', values: [], doc: 'Number of rows to span' },
    { name: 'headers', values: [], doc: 'Space-separated list of header cell IDs' },
  ],

  th: [
    { name: 'colspan', values: [], doc: 'Number of columns to span' },
    { name: 'rowspan', values: [], doc: 'Number of rows to span' },
    { name: 'headers', values: [], doc: 'Space-separated list of header cell IDs' },
    { name: 'scope', values: ['row', 'col', 'rowgroup', 'colgroup'], doc: 'Scope of header cell' },
    { name: 'abbr', values: [], doc: 'Abbreviated content for header' },
  ],

  // Scripts & Links
  script: [
    { name: 'src', values: [], doc: 'Script file URL' },
    { name: 'type', values: ['module', 'text/javascript', 'application/javascript'], doc: 'Script MIME type (use "module" for ES modules)' },
    { name: 'async', values: [], doc: 'Async execution (load in parallel, execute when ready)', boolean: true },
    { name: 'defer', values: [], doc: 'Deferred execution (load in parallel, execute after parsing)', boolean: true },
    { name: 'crossorigin', values: ['anonymous', 'use-credentials'], doc: 'CORS mode for cross-origin scripts' },
    { name: 'integrity', values: [], doc: 'Subresource integrity hash (e.g., sha384-...)' },
    { name: 'nomodule', values: [], doc: 'Skip in module-aware browsers (for legacy fallback)', boolean: true },
    { name: 'referrerpolicy', values: ['no-referrer', 'no-referrer-when-downgrade', 'origin', 'origin-when-cross-origin', 'same-origin', 'strict-origin', 'strict-origin-when-cross-origin', 'unsafe-url'], doc: 'Referrer policy for script fetch' },
  ],

  link: [
    { name: 'href', values: [], doc: 'Resource URL' },
    { name: 'rel', values: ['stylesheet', 'icon', 'preload', 'prefetch', 'dns-prefetch', 'preconnect', 'alternate', 'manifest', 'apple-touch-icon'], doc: 'Link relationship' },
    { name: 'type', values: ['text/css', 'image/x-icon', 'image/png', 'application/manifest+json'], doc: 'MIME type of linked resource' },
    { name: 'media', values: ['screen', 'print', '(max-width: 600px)', '(prefers-color-scheme: dark)'], doc: 'Media query for conditional loading' },
    { name: 'sizes', values: ['16x16', '32x32', '192x192', 'any'], doc: 'Icon sizes (for rel="icon")' },
    { name: 'crossorigin', values: ['anonymous', 'use-credentials'], doc: 'CORS mode for cross-origin resources' },
    { name: 'integrity', values: [], doc: 'Subresource integrity hash' },
    { name: 'referrerpolicy', values: ['no-referrer', 'no-referrer-when-downgrade', 'origin', 'origin-when-cross-origin', 'same-origin', 'strict-origin', 'strict-origin-when-cross-origin', 'unsafe-url'], doc: 'Referrer policy' },
    { name: 'as', values: ['audio', 'document', 'embed', 'fetch', 'font', 'image', 'object', 'script', 'style', 'track', 'video', 'worker'], doc: 'Preload resource type (for rel="preload")' },
    { name: 'fetchpriority', values: ['high', 'low', 'auto'], doc: 'Fetch priority hint' },
  ],

  style: [
    { name: 'media', values: ['screen', 'print', '(max-width: 600px)', '(prefers-color-scheme: dark)'], doc: 'Media query for conditional styles' },
    { name: 'type', values: ['text/css'], doc: 'MIME type (defaults to text/css)' },
  ],

  // iframes
  iframe: [
    { name: 'src', values: [], doc: 'Frame source URL' },
    { name: 'srcdoc', values: [], doc: 'Inline HTML document content' },
    { name: 'name', values: [], doc: 'Frame name (for targeting)' },
    { name: 'width', values: [], doc: 'Frame width in pixels' },
    { name: 'height', values: [], doc: 'Frame height in pixels' },
    { name: 'sandbox', values: ['allow-forms', 'allow-scripts', 'allow-same-origin', 'allow-popups', 'allow-modals', 'allow-downloads'], doc: 'Security restrictions (space-separated)' },
    { name: 'allow', values: ['camera', 'microphone', 'geolocation', 'fullscreen', 'payment', 'autoplay'], doc: 'Feature policy (semicolon-separated)' },
    { name: 'loading', values: ['lazy', 'eager'], doc: 'Loading strategy' },
    { name: 'referrerpolicy', values: ['no-referrer', 'no-referrer-when-downgrade', 'origin', 'origin-when-cross-origin', 'same-origin', 'strict-origin', 'strict-origin-when-cross-origin', 'unsafe-url'], doc: 'Referrer policy' },
  ],

  // Meta
  meta: [
    { name: 'charset', values: ['UTF-8'], doc: 'Character encoding (use UTF-8)' },
    { name: 'name', values: ['viewport', 'description', 'keywords', 'author', 'theme-color', 'robots'], doc: 'Metadata name' },
    { name: 'content', values: [], doc: 'Metadata value (depends on name attribute)' },
    { name: 'http-equiv', values: ['content-type', 'refresh', 'X-UA-Compatible', 'content-security-policy'], doc: 'HTTP header directive' },
  ],

  // Lists
  ol: [
    { name: 'reversed', values: [], doc: 'Reverse numbering order', boolean: true },
    { name: 'start', values: [], doc: 'Starting number' },
    { name: 'type', values: ['1', 'a', 'A', 'i', 'I'], doc: 'Numbering type (1=decimal, a=lowercase, A=uppercase, i=roman lowercase, I=roman uppercase)' },
  ],

  li: [
    { name: 'value', values: [], doc: 'List item number (for <ol> only)' },
  ],

  // Semantic elements
  details: [
    { name: 'open', values: [], doc: 'Expanded state', boolean: true },
  ],

  dialog: [
    { name: 'open', values: [], doc: 'Open dialog', boolean: true },
  ],

  time: [
    { name: 'datetime', values: [], doc: 'Machine-readable datetime (ISO 8601 format)' },
  ],

  meter: [
    { name: 'value', values: [], doc: 'Current value (required)' },
    { name: 'min', values: [], doc: 'Minimum value (default 0)' },
    { name: 'max', values: [], doc: 'Maximum value (default 1)' },
    { name: 'low', values: [], doc: 'Low threshold (considered suboptimal)' },
    { name: 'high', values: [], doc: 'High threshold (considered suboptimal)' },
    { name: 'optimum', values: [], doc: 'Optimal value' },
  ],

  progress: [
    { name: 'value', values: [], doc: 'Current progress value' },
    { name: 'max', values: [], doc: 'Maximum value (default 1)' },
  ],

  output: [
    { name: 'for', values: [], doc: 'Space-separated IDs of form controls that contributed to output' },
    { name: 'form', values: [], doc: 'Associated form ID' },
    { name: 'name', values: [], doc: 'Output name' },
  ],

  // Canvas
  canvas: [
    { name: 'width', values: [], doc: 'Canvas width in CSS pixels' },
    { name: 'height', values: [], doc: 'Canvas height in CSS pixels' },
  ],

  // Base
  base: [
    { name: 'href', values: [], doc: 'Base URL for all relative URLs in document' },
    { name: 'target', values: ['_blank', '_self', '_parent', '_top'], doc: 'Default target for all links' },
  ],

  // Area (for image maps)
  area: [
    { name: 'alt', values: [], doc: 'Alternative text (required)' },
    { name: 'coords', values: [], doc: 'Coordinates for clickable area' },
    { name: 'shape', values: ['rect', 'circle', 'poly', 'default'], doc: 'Shape of clickable area' },
    { name: 'href', values: [], doc: 'Link destination URL' },
    { name: 'target', values: ['_blank', '_self', '_parent', '_top'], doc: 'Where to open link' },
    { name: 'download', values: [], doc: 'Download filename' },
    { name: 'rel', values: ['noopener', 'noreferrer', 'nofollow'], doc: 'Link relationship' },
  ],
} as const;

/**
 * Get attributes for specific element
 * @param element - Element name (lowercase) or null
 * @returns Array of attributes (element-specific + global + ARIA)
 */
export function getAttributesFor(element: string | null): readonly AttributeData[] {
  if (!element) {
    // No element context - return only global + ARIA
    return [...GLOBAL_ATTRS, ...ARIA_ATTRS];
  }

  // Get element-specific attrs (or empty array if none exist)
  const elementAttrs = ELEMENT_ATTRS[element as keyof typeof ELEMENT_ATTRS] || [];

  // Combine: element-specific + global + ARIA
  // Element-specific first (higher priority in completions)
  return [...elementAttrs, ...GLOBAL_ATTRS, ...ARIA_ATTRS];
}
