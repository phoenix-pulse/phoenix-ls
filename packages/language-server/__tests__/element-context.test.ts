import { describe, it, expect } from 'vitest';
import {
  isFormElement,
  isFocusableElement,
  isButtonElement,
  isInputElement,
  getElementContext,
  shouldPrioritizeAttribute,
  FORM_SPECIFIC_ATTRIBUTES,
  FOCUSABLE_SPECIFIC_ATTRIBUTES,
} from '../src/utils/element-context';

describe('Element Context Detection', () => {
  describe('isFormElement', () => {
    it('should detect form elements', () => {
      expect(isFormElement('<form phx-submit="save" ')).toBe(true);
      expect(isFormElement('<form class="container" ')).toBe(true);
      expect(isFormElement('<form ')).toBe(true);
      expect(isFormElement('<form\n  phx-submit="save"\n  ')).toBe(true);
    });

    it('should not detect non-form elements', () => {
      expect(isFormElement('<div class="form" ')).toBe(false);
      expect(isFormElement('<input type="text" ')).toBe(false);
      expect(isFormElement('<button ')).toBe(false);
      expect(isFormElement('<span ')).toBe(false);
    });

    it('should handle edge cases', () => {
      expect(isFormElement('<formdata ')).toBe(false); // formdata is different
      expect(isFormElement('form')).toBe(false); // no opening bracket
      expect(isFormElement('<form>')).toBe(false); // no space after form
    });
  });

  describe('isFocusableElement', () => {
    it('should detect input elements', () => {
      expect(isFocusableElement('<input type="text" ')).toBe(true);
      expect(isFocusableElement('<input type="email" name="email" ')).toBe(true);
      expect(isFocusableElement('<input ')).toBe(true);
    });

    it('should detect textarea elements', () => {
      expect(isFocusableElement('<textarea name="content" ')).toBe(true);
      expect(isFocusableElement('<textarea ')).toBe(true);
    });

    it('should detect select elements', () => {
      expect(isFocusableElement('<select name="status" ')).toBe(true);
      expect(isFocusableElement('<select ')).toBe(true);
    });

    it('should detect button elements', () => {
      expect(isFocusableElement('<button type="submit" ')).toBe(true);
      expect(isFocusableElement('<button phx-click="save" ')).toBe(true);
      expect(isFocusableElement('<button ')).toBe(true);
    });

    it('should not detect non-focusable elements', () => {
      expect(isFocusableElement('<div ')).toBe(false);
      expect(isFocusableElement('<span ')).toBe(false);
      expect(isFocusableElement('<form ')).toBe(false);
      expect(isFocusableElement('<p ')).toBe(false);
    });
  });

  describe('isButtonElement', () => {
    it('should detect button elements', () => {
      expect(isButtonElement('<button type="submit" ')).toBe(true);
      expect(isButtonElement('<button ')).toBe(true);
    });

    it('should not detect non-button elements', () => {
      expect(isButtonElement('<input type="button" ')).toBe(false);
      expect(isButtonElement('<div ')).toBe(false);
    });
  });

  describe('isInputElement', () => {
    it('should detect input elements', () => {
      expect(isInputElement('<input type="text" ')).toBe(true);
      expect(isInputElement('<input ')).toBe(true);
    });

    it('should not detect non-input elements', () => {
      expect(isInputElement('<button ')).toBe(false);
      expect(isInputElement('<textarea ')).toBe(false);
    });
  });

  describe('getElementContext', () => {
    it('should return "form" for form elements', () => {
      expect(getElementContext('<form phx-submit="save" ')).toBe('form');
      expect(getElementContext('<form class="container" ')).toBe('form');
    });

    it('should return "input" for input elements', () => {
      expect(getElementContext('<input type="text" ')).toBe('input');
      expect(getElementContext('<input type="email" name="email" ')).toBe('input');
    });

    it('should return "button" for button elements', () => {
      expect(getElementContext('<button type="submit" ')).toBe('button');
      expect(getElementContext('<button phx-click="save" ')).toBe('button');
    });

    it('should return "generic" for non-specific elements', () => {
      expect(getElementContext('<div ')).toBe('generic');
      expect(getElementContext('<span ')).toBe('generic');
      expect(getElementContext('<p ')).toBe('generic');
      expect(getElementContext('<section ')).toBe('generic');
    });

    it('should prioritize most specific context', () => {
      // Input is more specific than focusable
      expect(getElementContext('<input type="text" ')).toBe('input');

      // Button is more specific than focusable
      expect(getElementContext('<button type="submit" ')).toBe('button');

      // Textarea returns generic (not explicitly handled as special case)
      expect(getElementContext('<textarea ')).toBe('generic');
    });
  });

  describe('shouldPrioritizeAttribute', () => {
    describe('form context', () => {
      it('should prioritize form-specific attributes', () => {
        FORM_SPECIFIC_ATTRIBUTES.forEach((attr) => {
          expect(shouldPrioritizeAttribute(attr, 'form')).toBe(true);
        });
      });

      it('should not prioritize non-form attributes', () => {
        expect(shouldPrioritizeAttribute('phx-click', 'form')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-blur', 'form')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-focus', 'form')).toBe(false);
      });

      it('should prioritize specific form attributes', () => {
        expect(shouldPrioritizeAttribute('phx-change', 'form')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-submit', 'form')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-auto-recover', 'form')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-trigger-action', 'form')).toBe(true);
      });
    });

    describe('input context', () => {
      it('should prioritize focusable attributes', () => {
        FOCUSABLE_SPECIFIC_ATTRIBUTES.forEach((attr) => {
          expect(shouldPrioritizeAttribute(attr, 'input')).toBe(true);
        });
      });

      it('should not prioritize form-specific attributes', () => {
        expect(shouldPrioritizeAttribute('phx-submit', 'input')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-change', 'input')).toBe(false);
      });

      it('should prioritize specific focusable attributes', () => {
        expect(shouldPrioritizeAttribute('phx-blur', 'input')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-focus', 'input')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-disable-with', 'input')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-window-blur', 'input')).toBe(true);
        expect(shouldPrioritizeAttribute('phx-window-focus', 'input')).toBe(true);
      });
    });

    describe('button context', () => {
      it('should prioritize focusable attributes', () => {
        FOCUSABLE_SPECIFIC_ATTRIBUTES.forEach((attr) => {
          expect(shouldPrioritizeAttribute(attr, 'button')).toBe(true);
        });
      });

      it('should prioritize phx-disable-with for buttons', () => {
        expect(shouldPrioritizeAttribute('phx-disable-with', 'button')).toBe(true);
      });
    });

    describe('generic context', () => {
      it('should not prioritize any attributes', () => {
        expect(shouldPrioritizeAttribute('phx-click', 'generic')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-submit', 'generic')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-blur', 'generic')).toBe(false);
        expect(shouldPrioritizeAttribute('phx-change', 'generic')).toBe(false);
      });
    });
  });

  describe('attribute constants', () => {
    it('should define form-specific attributes', () => {
      expect(FORM_SPECIFIC_ATTRIBUTES).toEqual([
        'phx-change',
        'phx-submit',
        'phx-auto-recover',
        'phx-trigger-action',
      ]);
    });

    it('should define focusable-specific attributes', () => {
      expect(FOCUSABLE_SPECIFIC_ATTRIBUTES).toEqual([
        'phx-blur',
        'phx-focus',
        'phx-disable-with',
        'phx-window-blur',
        'phx-window-focus',
      ]);
    });
  });
});
