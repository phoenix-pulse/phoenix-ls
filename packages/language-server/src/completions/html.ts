import { CompletionItem, CompletionItemKind, InsertTextFormat } from 'vscode-languageserver/node';

// Common HTML attributes
const htmlAttributes = [
  // Global attributes
  { label: 'id', detail: 'Element identifier', insertText: 'id="${1:value}"' },
  { label: 'class', detail: 'CSS classes', insertText: 'class="${1:value}"' },
  { label: 'style', detail: 'Inline CSS styles', insertText: 'style="${1:property: value;}"' },
  { label: 'title', detail: 'Advisory information', insertText: 'title="${1:text}"' },
  { label: 'lang', detail: 'Language code', insertText: 'lang="${1:en}"' },
  { label: 'dir', detail: 'Text direction', insertText: 'dir="${1|ltr,rtl|}"' },
  { label: 'tabindex', detail: 'Tab order', insertText: 'tabindex="${1:0}"' },
  { label: 'accesskey', detail: 'Keyboard shortcut', insertText: 'accesskey="${1:key}"' },
  { label: 'contenteditable', detail: 'Editable content', insertText: 'contenteditable="${1|true,false|}"' },
  { label: 'draggable', detail: 'Draggable element', insertText: 'draggable="${1|true,false|}"' },
  { label: 'hidden', detail: 'Hidden element', insertText: 'hidden' },
  { label: 'spellcheck', detail: 'Spell checking', insertText: 'spellcheck="${1|true,false|}"' },

  // Data attributes
  { label: 'data-', detail: 'Custom data attribute', insertText: 'data-${1:name}="${2:value}"' },

  // ARIA attributes
  { label: 'role', detail: 'ARIA role', insertText: 'role="${1:button}"' },
  { label: 'aria-label', detail: 'Accessible label', insertText: 'aria-label="${1:description}"' },
  { label: 'aria-labelledby', detail: 'Referenced label', insertText: 'aria-labelledby="${1:id}"' },
  { label: 'aria-describedby', detail: 'Referenced description', insertText: 'aria-describedby="${1:id}"' },
  { label: 'aria-hidden', detail: 'Hidden from screen readers', insertText: 'aria-hidden="${1|true,false|}"' },
  { label: 'aria-expanded', detail: 'Expanded state', insertText: 'aria-expanded="${1|true,false|}"' },
  { label: 'aria-controls', detail: 'Controlled element', insertText: 'aria-controls="${1:id}"' },
  { label: 'aria-live', detail: 'Live region', insertText: 'aria-live="${1|polite,assertive,off|}"' },

  // Form attributes
  { label: 'name', detail: 'Form control name', insertText: 'name="${1:name}"' },
  { label: 'value', detail: 'Form control value', insertText: 'value="${1:value}"' },
  { label: 'type', detail: 'Input type', insertText: 'type="${1:text}"' },
  { label: 'placeholder', detail: 'Placeholder text', insertText: 'placeholder="${1:text}"' },
  { label: 'required', detail: 'Required field', insertText: 'required' },
  { label: 'disabled', detail: 'Disabled field', insertText: 'disabled' },
  { label: 'readonly', detail: 'Read-only field', insertText: 'readonly' },
  { label: 'checked', detail: 'Checked state', insertText: 'checked' },
  { label: 'selected', detail: 'Selected option', insertText: 'selected' },
  { label: 'multiple', detail: 'Multiple selection', insertText: 'multiple' },
  { label: 'autofocus', detail: 'Auto focus', insertText: 'autofocus' },
  { label: 'autocomplete', detail: 'Autocomplete', insertText: 'autocomplete="${1|on,off|}"' },
  { label: 'pattern', detail: 'Validation pattern', insertText: 'pattern="${1:regex}"' },
  { label: 'min', detail: 'Minimum value', insertText: 'min="${1:0}"' },
  { label: 'max', detail: 'Maximum value', insertText: 'max="${1:100}"' },
  { label: 'step', detail: 'Value step', insertText: 'step="${1:1}"' },
  { label: 'maxlength', detail: 'Maximum length', insertText: 'maxlength="${1:100}"' },
  { label: 'minlength', detail: 'Minimum length', insertText: 'minlength="${1:1}"' },

  // Link and media attributes
  { label: 'href', detail: 'Link URL', insertText: 'href="${1:url}"' },
  { label: 'src', detail: 'Resource URL', insertText: 'src="${1:url}"' },
  { label: 'alt', detail: 'Alternative text', insertText: 'alt="${1:description}"' },
  { label: 'target', detail: 'Link target', insertText: 'target="${1|_blank,_self,_parent,_top|}"' },
  { label: 'rel', detail: 'Link relationship', insertText: 'rel="${1:noopener}"' },
  { label: 'download', detail: 'Download link', insertText: 'download="${1:filename}"' },

  // Event handlers
  { label: 'onclick', detail: 'Click handler', insertText: 'onclick="${1:handler()}"' },
  { label: 'onchange', detail: 'Change handler', insertText: 'onchange="${1:handler()}"' },
  { label: 'onsubmit', detail: 'Submit handler', insertText: 'onsubmit="${1:handler()}"' },
  { label: 'oninput', detail: 'Input handler', insertText: 'oninput="${1:handler()}"' },
  { label: 'onfocus', detail: 'Focus handler', insertText: 'onfocus="${1:handler()}"' },
  { label: 'onblur', detail: 'Blur handler', insertText: 'onblur="${1:handler()}"' },
  { label: 'onload', detail: 'Load handler', insertText: 'onload="${1:handler()}"' },
  { label: 'onerror', detail: 'Error handler', insertText: 'onerror="${1:handler()}"' },
];

export function getHtmlCompletions(): CompletionItem[] {
  return htmlAttributes.map((attr, index) => ({
    label: attr.label,
    kind: CompletionItemKind.Property,
    detail: attr.detail,
    documentation: 'HTML attribute',
    insertText: attr.insertText,
    insertTextFormat: InsertTextFormat.Snippet,
    sortText: `!7${index.toString().padStart(3, '0')}`, // Sort after Phoenix attrs
  }));
}
