import { describe, it, expect } from 'vitest';
import { getPhoenixCompletions } from '../src/completions/phoenix';
import { MarkupKind } from 'vscode-languageserver/node';

describe('Context-Aware Phoenix Completions', () => {
  describe('getPhoenixCompletions', () => {
    it('should return all Phoenix attributes', () => {
      const completions = getPhoenixCompletions();
      expect(completions.length).toBeGreaterThan(0);

      // Verify some key attributes exist
      const labels = completions.map((c) => c.label);
      expect(labels).toContain('phx-click');
      expect(labels).toContain('phx-submit');
      expect(labels).toContain('phx-change');
      expect(labels).toContain('phx-blur');
      expect(labels).toContain('phx-focus');
    });

    it('should use MarkupKind.Markdown for documentation', () => {
      const completions = getPhoenixCompletions();

      completions.forEach((completion) => {
        expect(completion.documentation).toBeDefined();
        expect(completion.documentation).toHaveProperty('kind');
        expect(completion.documentation).toHaveProperty('value');
        expect((completion.documentation as any).kind).toBe(MarkupKind.Markdown);
        expect(typeof (completion.documentation as any).value).toBe('string');
        expect((completion.documentation as any).value.length).toBeGreaterThan(0);
      });
    });

    describe('without context (generic)', () => {
      it('should return completions with standard sorting', () => {
        const completions = getPhoenixCompletions();

        // All should have !6 prefix (no priority)
        completions.forEach((completion) => {
          expect(completion.sortText).toMatch(/^!6\d{3}$/);
        });
      });

      it('should not prioritize any attributes', () => {
        const completions = getPhoenixCompletions('generic');

        // All should have !6 prefix (no priority)
        completions.forEach((completion) => {
          expect(completion.sortText).toMatch(/^!6\d{3}$/);
        });
      });
    });

    describe('form context', () => {
      it('should prioritize form-specific attributes', () => {
        const completions = getPhoenixCompletions('form');

        // Find form-specific attributes
        const phxSubmit = completions.find((c) => c.label === 'phx-submit');
        const phxChange = completions.find((c) => c.label === 'phx-change');
        const phxAutoRecover = completions.find((c) => c.label === 'phx-auto-recover');
        const phxTriggerAction = completions.find((c) => c.label === 'phx-trigger-action');

        // These should be prioritized (!0 prefix)
        expect(phxSubmit?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxChange?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxAutoRecover?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxTriggerAction?.sortText).toMatch(/^!0\d{3}$/);

        // Non-form attributes should not be prioritized (!6 prefix)
        const phxClick = completions.find((c) => c.label === 'phx-click');
        const phxBlur = completions.find((c) => c.label === 'phx-blur');

        expect(phxClick?.sortText).toMatch(/^!6\d{3}$/);
        expect(phxBlur?.sortText).toMatch(/^!6\d{3}$/);
      });

      it('should sort prioritized attributes before others', () => {
        const completions = getPhoenixCompletions('form');

        const phxSubmit = completions.find((c) => c.label === 'phx-submit');
        const phxClick = completions.find((c) => c.label === 'phx-click');

        // Prioritized (!0) should sort before non-prioritized (!6)
        expect(phxSubmit?.sortText! < phxClick?.sortText!).toBe(true);
      });
    });

    describe('input context', () => {
      it('should prioritize focusable attributes', () => {
        const completions = getPhoenixCompletions('input');

        // Find focusable attributes
        const phxBlur = completions.find((c) => c.label === 'phx-blur');
        const phxFocus = completions.find((c) => c.label === 'phx-focus');
        const phxDisableWith = completions.find((c) => c.label === 'phx-disable-with');
        const phxWindowBlur = completions.find((c) => c.label === 'phx-window-blur');
        const phxWindowFocus = completions.find((c) => c.label === 'phx-window-focus');

        // These should be prioritized (!0 prefix)
        expect(phxBlur?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxFocus?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxDisableWith?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxWindowBlur?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxWindowFocus?.sortText).toMatch(/^!0\d{3}$/);

        // Non-focusable attributes should not be prioritized (!6 prefix)
        const phxSubmit = completions.find((c) => c.label === 'phx-submit');
        const phxChange = completions.find((c) => c.label === 'phx-change');

        expect(phxSubmit?.sortText).toMatch(/^!6\d{3}$/);
        expect(phxChange?.sortText).toMatch(/^!6\d{3}$/);
      });

      it('should sort prioritized attributes before others', () => {
        const completions = getPhoenixCompletions('input');

        const phxBlur = completions.find((c) => c.label === 'phx-blur');
        const phxClick = completions.find((c) => c.label === 'phx-click');

        // Prioritized (!0) should sort before non-prioritized (!6)
        expect(phxBlur?.sortText! < phxClick?.sortText!).toBe(true);
      });
    });

    describe('button context', () => {
      it('should prioritize focusable attributes', () => {
        const completions = getPhoenixCompletions('button');

        // Find focusable attributes
        const phxBlur = completions.find((c) => c.label === 'phx-blur');
        const phxFocus = completions.find((c) => c.label === 'phx-focus');
        const phxDisableWith = completions.find((c) => c.label === 'phx-disable-with');

        // These should be prioritized (!0 prefix)
        expect(phxBlur?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxFocus?.sortText).toMatch(/^!0\d{3}$/);
        expect(phxDisableWith?.sortText).toMatch(/^!0\d{3}$/);

        // Form-specific attributes should not be prioritized (!6 prefix)
        const phxSubmit = completions.find((c) => c.label === 'phx-submit');
        const phxChange = completions.find((c) => c.label === 'phx-change');

        expect(phxSubmit?.sortText).toMatch(/^!6\d{3}$/);
        expect(phxChange?.sortText).toMatch(/^!6\d{3}$/);
      });
    });

    describe('completion item structure', () => {
      it('should have required completion item properties', () => {
        const completions = getPhoenixCompletions();

        completions.forEach((completion) => {
          // Required properties
          expect(completion).toHaveProperty('label');
          expect(completion).toHaveProperty('kind');
          expect(completion).toHaveProperty('detail');
          expect(completion).toHaveProperty('documentation');
          expect(completion).toHaveProperty('insertText');
          expect(completion).toHaveProperty('insertTextFormat');
          expect(completion).toHaveProperty('sortText');

          // Types
          expect(typeof completion.label).toBe('string');
          expect(typeof completion.detail).toBe('string');
          expect(typeof completion.insertText).toBe('string');
          expect(typeof completion.sortText).toBe('string');
        });
      });

      it('should have valid insert text snippets', () => {
        const completions = getPhoenixCompletions();

        completions.forEach((completion) => {
          // Insert text should contain the attribute name
          expect(completion.insertText).toContain(completion.label);
        });
      });
    });

    describe('priority sorting edge cases', () => {
      it('should handle undefined context gracefully', () => {
        const completions = getPhoenixCompletions(undefined);

        // Should default to non-prioritized (!6 prefix)
        completions.forEach((completion) => {
          expect(completion.sortText).toMatch(/^!6\d{3}$/);
        });
      });

      it('should maintain relative order within priority groups', () => {
        const formCompletions = getPhoenixCompletions('form');

        // Get all prioritized form attributes
        const prioritized = formCompletions.filter((c) =>
          c.sortText!.startsWith('!0')
        );

        // Each should have unique sortText
        const sortTexts = prioritized.map((c) => c.sortText);
        const uniqueSortTexts = new Set(sortTexts);
        expect(sortTexts.length).toBe(uniqueSortTexts.size);
      });
    });

    describe('comprehensive attribute coverage', () => {
      it('should include all major Phoenix attribute categories', () => {
        const completions = getPhoenixCompletions();
        const labels = completions.map((c) => c.label);

        // Event bindings
        expect(labels).toContain('phx-click');
        expect(labels).toContain('phx-change');
        expect(labels).toContain('phx-submit');
        expect(labels).toContain('phx-blur');
        expect(labels).toContain('phx-focus');

        // Key events
        expect(labels).toContain('phx-keydown');
        expect(labels).toContain('phx-keyup');
        expect(labels).toContain('phx-window-keydown');
        expect(labels).toContain('phx-window-keyup');

        // Value passing
        expect(labels).toContain('phx-value-');

        // Rate limiting
        expect(labels).toContain('phx-debounce');
        expect(labels).toContain('phx-throttle');

        // Update control
        expect(labels).toContain('phx-update');

        // Hooks
        expect(labels).toContain('phx-hook');

        // Feedback
        expect(labels).toContain('phx-disable-with');

        // Form-specific
        expect(labels).toContain('phx-auto-recover');
        expect(labels).toContain('phx-trigger-action');
      });
    });
  });
});
