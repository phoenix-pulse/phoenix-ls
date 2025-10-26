import { describe, it, expect } from 'vitest';
import { getPhoenixCompletions } from '../src/completions/phoenix';

describe('Event-Aware Phoenix Attributes', () => {
  describe('when LiveView has NO events (hasEvents = false)', () => {
    it('should not prioritize event-triggering attributes', () => {
      const completions = getPhoenixCompletions('generic', false);

      // All should have !6 prefix (no priority)
      completions.forEach((completion) => {
        expect(completion.sortText).toMatch(/^!6\d{3}$/);
      });
    });

    it('should NOT show lightning bolt emoji', () => {
      const completions = getPhoenixCompletions('generic', false);

      completions.forEach((completion) => {
        expect(completion.detail).not.toContain('⚡');
      });
    });
  });

  describe('when LiveView has events (hasEvents = true)', () => {
    it('should prioritize event-triggering attributes', () => {
      const completions = getPhoenixCompletions('generic', true);

      // Event-triggering attributes
      const phxClick = completions.find((c) => c.label === 'phx-click');
      const phxSubmit = completions.find((c) => c.label === 'phx-submit');
      const phxChange = completions.find((c) => c.label === 'phx-change');
      const phxBlur = completions.find((c) => c.label === 'phx-blur');

      // These should be prioritized (!0 prefix)
      expect(phxClick?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxSubmit?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxChange?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxBlur?.sortText).toMatch(/^!0\d{3}$/);

      // Non-event attributes should not be prioritized (!6 prefix)
      const phxUpdate = completions.find((c) => c.label === 'phx-update');
      const phxHook = completions.find((c) => c.label === 'phx-hook');

      expect(phxUpdate?.sortText).toMatch(/^!6\d{3}$/);
      expect(phxHook?.sortText).toMatch(/^!6\d{3}$/);
    });

    it('should show lightning bolt emoji for event-triggering attributes', () => {
      const completions = getPhoenixCompletions('generic', true);

      // Event-triggering attributes should have ⚡
      const eventAttrs = [
        'phx-click',
        'phx-submit',
        'phx-change',
        'phx-blur',
        'phx-focus',
        'phx-keydown',
        'phx-keyup',
      ];

      eventAttrs.forEach((attrName) => {
        const attr = completions.find((c) => c.label === attrName);
        expect(attr?.detail).toContain('⚡');
      });

      // Non-event attributes should NOT have ⚡
      const nonEventAttrs = ['phx-update', 'phx-hook', 'phx-debounce', 'phx-throttle'];

      nonEventAttrs.forEach((attrName) => {
        const attr = completions.find((c) => c.label === attrName);
        expect(attr?.detail).not.toContain('⚡');
      });
    });

    it('should prioritize all event-triggering attributes defined in constant', () => {
      const completions = getPhoenixCompletions('generic', true);

      const expectedEventAttrs = [
        'phx-click',
        'phx-submit',
        'phx-change',
        'phx-blur',
        'phx-focus',
        'phx-keydown',
        'phx-keyup',
        'phx-window-keydown',
        'phx-window-keyup',
        'phx-window-blur',
        'phx-window-focus',
        'phx-capture-click',
        'phx-click-away',
        'phx-viewport-top',
        'phx-viewport-bottom',
      ];

      expectedEventAttrs.forEach((attrName) => {
        const attr = completions.find((c) => c.label === attrName);
        expect(attr?.sortText).toMatch(/^!0\d{3}$/);
        expect(attr?.detail).toContain('⚡');
      });
    });
  });

  describe('combined with element context prioritization', () => {
    it('should prioritize form attrs in form context even without events', () => {
      const completions = getPhoenixCompletions('form', false);

      const phxSubmit = completions.find((c) => c.label === 'phx-submit');
      const phxChange = completions.find((c) => c.label === 'phx-change');

      // Form-specific attrs prioritized by context (!0 prefix)
      expect(phxSubmit?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxChange?.sortText).toMatch(/^!0\d{3}$/);

      // But no ⚡ emoji because hasEvents = false
      expect(phxSubmit?.detail).not.toContain('⚡');
      expect(phxChange?.detail).not.toContain('⚡');
    });

    it('should prioritize form attrs AND show emoji when both conditions true', () => {
      const completions = getPhoenixCompletions('form', true);

      const phxSubmit = completions.find((c) => c.label === 'phx-submit');
      const phxChange = completions.find((c) => c.label === 'phx-change');

      // Form-specific attrs prioritized (!0 prefix)
      expect(phxSubmit?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxChange?.sortText).toMatch(/^!0\d{3}$/);

      // AND show ⚡ emoji because hasEvents = true
      expect(phxSubmit?.detail).toContain('⚡');
      expect(phxChange?.detail).toContain('⚡');
    });

    it('should prioritize event attrs in input context when events exist', () => {
      const completions = getPhoenixCompletions('input', true);

      const phxBlur = completions.find((c) => c.label === 'phx-blur');
      const phxFocus = completions.find((c) => c.label === 'phx-focus');
      const phxClick = completions.find((c) => c.label === 'phx-click');

      // All prioritized - phx-blur/focus by input context, phx-click by events
      expect(phxBlur?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxFocus?.sortText).toMatch(/^!0\d{3}$/);
      expect(phxClick?.sortText).toMatch(/^!0\d{3}$/);

      // All show ⚡ emoji because they're event-triggering
      expect(phxBlur?.detail).toContain('⚡');
      expect(phxFocus?.detail).toContain('⚡');
      expect(phxClick?.detail).toContain('⚡');
    });

    it('should NOT prioritize non-event attrs in input context even with events', () => {
      const completions = getPhoenixCompletions('input', true);

      const phxUpdate = completions.find((c) => c.label === 'phx-update');
      const phxHook = completions.find((c) => c.label === 'phx-hook');

      // Not prioritized (!6 prefix)
      expect(phxUpdate?.sortText).toMatch(/^!6\d{3}$/);
      expect(phxHook?.sortText).toMatch(/^!6\d{3}$/);

      // No ⚡ emoji (not event-triggering)
      expect(phxUpdate?.detail).not.toContain('⚡');
      expect(phxHook?.detail).not.toContain('⚡');
    });
  });

  describe('backward compatibility', () => {
    it('should work without hasEvents parameter (undefined)', () => {
      const completions = getPhoenixCompletions('generic', undefined);

      // Should default to no event prioritization
      completions.forEach((completion) => {
        if (
          !['phx-submit', 'phx-change', 'phx-auto-recover', 'phx-trigger-action'].includes(
            completion.label
          )
        ) {
          // Non-form attrs should have !6 prefix
          expect(completion.sortText).toMatch(/^!6\d{3}$/);
        }
      });

      // No ⚡ emoji when hasEvents is undefined
      completions.forEach((completion) => {
        expect(completion.detail).not.toContain('⚡');
      });
    });

    it('should work with only context parameter (old API)', () => {
      const completions = getPhoenixCompletions('form');

      const phxSubmit = completions.find((c) => c.label === 'phx-submit');

      // Form context prioritization still works
      expect(phxSubmit?.sortText).toMatch(/^!0\d{3}$/);

      // But no ⚡ emoji (hasEvents not provided)
      expect(phxSubmit?.detail).not.toContain('⚡');
    });
  });

  describe('sorting behavior', () => {
    it('should sort prioritized attributes before non-prioritized', () => {
      const completions = getPhoenixCompletions('generic', true);

      const phxClick = completions.find((c) => c.label === 'phx-click');
      const phxUpdate = completions.find((c) => c.label === 'phx-update');

      // Prioritized (!0) should sort before non-prioritized (!6)
      expect(phxClick?.sortText! < phxUpdate?.sortText!).toBe(true);
    });

    it('should maintain relative order within same priority group', () => {
      const completions = getPhoenixCompletions('generic', true);

      // Get all prioritized event attrs
      const prioritized = completions.filter((c) => c.sortText!.startsWith('!0'));

      // Each should have unique sortText
      const sortTexts = prioritized.map((c) => c.sortText);
      const uniqueSortTexts = new Set(sortTexts);
      expect(sortTexts.length).toBe(uniqueSortTexts.size);
    });
  });

  describe('completion item structure', () => {
    it('should preserve all required completion item properties', () => {
      const completions = getPhoenixCompletions('generic', true);

      completions.forEach((completion) => {
        expect(completion).toHaveProperty('label');
        expect(completion).toHaveProperty('kind');
        expect(completion).toHaveProperty('detail');
        expect(completion).toHaveProperty('documentation');
        expect(completion).toHaveProperty('insertText');
        expect(completion).toHaveProperty('insertTextFormat');
        expect(completion).toHaveProperty('sortText');
      });
    });

    it('should preserve MarkupKind.Markdown documentation', () => {
      const completions = getPhoenixCompletions('generic', true);

      completions.forEach((completion) => {
        expect(completion.documentation).toHaveProperty('kind');
        expect(completion.documentation).toHaveProperty('value');
        expect((completion.documentation as any).kind).toBe('markdown'); // MarkupKind.Markdown
        expect(typeof (completion.documentation as any).value).toBe('string');
      });
    });
  });
});
