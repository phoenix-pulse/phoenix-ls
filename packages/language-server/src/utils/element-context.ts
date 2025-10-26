/**
 * Element context detection utilities
 *
 * These utilities help determine what type of HTML element the cursor is currently in,
 * allowing for context-aware attribute completions.
 */

/**
 * Element context types for prioritizing attribute completions
 */
export type ElementContext = 'form' | 'input' | 'button' | 'generic';

/**
 * Detects if the cursor is inside a <form> tag
 *
 * @param linePrefix - Text before the cursor
 * @returns true if inside a form element
 *
 * @example
 * isFormElement('<form phx-submit="save" ')  // true
 * isFormElement('<div class="container" ')   // false
 */
export function isFormElement(linePrefix: string): boolean {
  // Look for <form followed by whitespace and attributes
  return /<form\s+[^>]*$/.test(linePrefix);
}

/**
 * Detects if the cursor is inside a focusable element (input, textarea, select, button)
 * These elements can receive phx-blur, phx-focus, phx-disable-with, etc.
 *
 * @param linePrefix - Text before the cursor
 * @returns true if inside a focusable element
 *
 * @example
 * isFocusableElement('<input type="text" ')     // true
 * isFocusableElement('<button phx-click="save" ') // true
 * isFocusableElement('<div class="btn" ')       // false
 */
export function isFocusableElement(linePrefix: string): boolean {
  // Match input, textarea, select, or button tags
  return /<(input|textarea|select|button)\s+[^>]*$/.test(linePrefix);
}

/**
 * Detects if the cursor is inside a button element
 *
 * @param linePrefix - Text before the cursor
 * @returns true if inside a button element
 */
export function isButtonElement(linePrefix: string): boolean {
  return /<button\s+[^>]*$/.test(linePrefix);
}

/**
 * Detects if the cursor is inside an input element
 *
 * @param linePrefix - Text before the cursor
 * @returns true if inside an input element
 */
export function isInputElement(linePrefix: string): boolean {
  return /<input\s+[^>]*$/.test(linePrefix);
}

/**
 * Gets the element context for the current cursor position
 * Returns the most specific context to allow for prioritized completions
 *
 * @param linePrefix - Text before the cursor
 * @returns ElementContext type
 *
 * @example
 * getElementContext('<form phx-submit="save" ')  // 'form'
 * getElementContext('<input type="text" ')       // 'input'
 * getElementContext('<button ')                  // 'button'
 * getElementContext('<div ')                     // 'generic'
 */
export function getElementContext(linePrefix: string): ElementContext {
  // Check most specific contexts first
  if (isFormElement(linePrefix)) {
    return 'form';
  }

  if (isInputElement(linePrefix)) {
    return 'input';
  }

  if (isButtonElement(linePrefix)) {
    return 'button';
  }

  // Fallback to generic (matches any HTML element)
  return 'generic';
}

/**
 * List of Phoenix attributes that are specific to form elements
 * These should be prioritized when inside <form> tags
 */
export const FORM_SPECIFIC_ATTRIBUTES = [
  'phx-change',
  'phx-submit',
  'phx-auto-recover',
  'phx-trigger-action',
];

/**
 * List of Phoenix attributes that are specific to focusable elements
 * These should be prioritized when inside input, textarea, select, button elements
 */
export const FOCUSABLE_SPECIFIC_ATTRIBUTES = [
  'phx-blur',
  'phx-focus',
  'phx-disable-with',
  'phx-window-blur',
  'phx-window-focus',
];

/**
 * Determines if an attribute should be prioritized for the given element context
 *
 * @param attributeName - The Phoenix attribute name (e.g., 'phx-submit')
 * @param context - The current element context
 * @returns true if the attribute should be prioritized
 */
export function shouldPrioritizeAttribute(
  attributeName: string,
  context: ElementContext
): boolean {
  switch (context) {
    case 'form':
      return FORM_SPECIFIC_ATTRIBUTES.includes(attributeName);

    case 'input':
    case 'button':
      return FOCUSABLE_SPECIFIC_ATTRIBUTES.includes(attributeName);

    case 'generic':
    default:
      return false;
  }
}
