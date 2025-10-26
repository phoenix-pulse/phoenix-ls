import { describe, it, expect } from 'vitest';
import { getSpecialAttributeCompletions } from '../src/completions/special-attributes';
import { MarkupKind, CompletionItemKind } from 'vscode-languageserver/node';

describe('Special Attributes Completions', () => {
  describe('getSpecialAttributeCompletions', () => {
    it('should return all 4 special attributes', () => {
      const completions = getSpecialAttributeCompletions();

      expect(completions).toHaveLength(4);

      const labels = completions.map((c) => c.label);
      expect(labels).toContain(':for');
      expect(labels).toContain(':if');
      expect(labels).toContain(':let');
      expect(labels).toContain(':key');
    });

    it('should use MarkupKind.Markdown for documentation', () => {
      const completions = getSpecialAttributeCompletions();

      completions.forEach((completion) => {
        expect(completion.documentation).toBeDefined();
        expect(completion.documentation).toHaveProperty('kind');
        expect(completion.documentation).toHaveProperty('value');
        expect((completion.documentation as any).kind).toBe(MarkupKind.Markdown);
        expect(typeof (completion.documentation as any).value).toBe('string');
      });
    });

    it('should have rich documentation with examples', () => {
      const completions = getSpecialAttributeCompletions();

      completions.forEach((completion) => {
        const doc = (completion.documentation as any).value;

        // All should have code examples
        expect(doc).toContain('```heex');

        // All should have HexDocs link
        expect(doc).toContain('[📖 HexDocs]');
        expect(doc).toContain('https://hexdocs.pm/phoenix_live_view');
      });
    });

    describe(':for attribute', () => {
      it('should have comprehensive loop documentation', () => {
        const completions = getSpecialAttributeCompletions();
        const forAttr = completions.find((c) => c.label === ':for');

        expect(forAttr).toBeDefined();
        expect(forAttr?.label).toBe(':for');
        expect(forAttr?.detail).toBe('Loop comprehension');

        const doc = (forAttr?.documentation as any).value;

        // Should cover multiple use cases
        expect(doc).toContain('Basic Loop');
        expect(doc).toContain('Pattern Matching');
        expect(doc).toContain('Index');
        expect(doc).toContain('Guards');

        // Should mention best practices
        expect(doc).toContain('Best Practices');
        expect(doc).toContain(':key');

        // Should have code examples
        expect(doc).toContain('item <- @items');
        expect(doc).toContain('Enum.with_index');
      });

      it('should have correct insert text snippet', () => {
        const completions = getSpecialAttributeCompletions();
        const forAttr = completions.find((c) => c.label === ':for');

        expect(forAttr?.insertText).toContain(':for=');
        expect(forAttr?.insertText).toContain('<-');
        expect(forAttr?.insertText).toContain('${'); // Snippet placeholder
      });
    });

    describe(':if attribute', () => {
      it('should have comprehensive conditional documentation', () => {
        const completions = getSpecialAttributeCompletions();
        const ifAttr = completions.find((c) => c.label === ':if');

        expect(ifAttr).toBeDefined();
        expect(ifAttr?.label).toBe(':if');
        expect(ifAttr?.detail).toBe('Conditional rendering');

        const doc = (ifAttr?.documentation as any).value;

        // Should cover multiple scenarios
        expect(doc).toContain('Basic Conditional');
        expect(doc).toContain('Negation');
        expect(doc).toContain('Complex Conditions');
        expect(doc).toContain('Pattern Matching');

        // Should explain behavior
        expect(doc).toContain('removed from the DOM');

        // Should mention best practices
        expect(doc).toContain('Best Practices');
        expect(doc).toContain('No else clause');
      });

      it('should have correct insert text snippet', () => {
        const completions = getSpecialAttributeCompletions();
        const ifAttr = completions.find((c) => c.label === ':if');

        expect(ifAttr?.insertText).toContain(':if=');
        expect(ifAttr?.insertText).toContain('@'); // Assign reference
        expect(ifAttr?.insertText).toContain('${'); // Snippet placeholder
      });
    });

    describe(':let attribute', () => {
      it('should have comprehensive yield documentation', () => {
        const completions = getSpecialAttributeCompletions();
        const letAttr = completions.find((c) => c.label === ':let');

        expect(letAttr).toBeDefined();
        expect(letAttr?.label).toBe(':let');
        expect(letAttr?.detail).toBe('Yield value from component/slot');

        const doc = (letAttr?.documentation as any).value;

        // Should cover multiple use cases
        expect(doc).toContain('Form Components');
        expect(doc).toContain('Async Assigns');
        expect(doc).toContain('Slots');
        expect(doc).toContain('Custom Components');

        // Should explain how it works
        expect(doc).toContain('How It Works');
        expect(doc).toContain('render_slot');

        // Should show pattern matching
        expect(doc).toContain('Pattern Matching');
      });

      it('should have correct insert text snippet', () => {
        const completions = getSpecialAttributeCompletions();
        const letAttr = completions.find((c) => c.label === ':let');

        expect(letAttr?.insertText).toContain(':let=');
        expect(letAttr?.insertText).toContain('${'); // Snippet placeholder
      });
    });

    describe(':key attribute', () => {
      it('should have comprehensive key documentation', () => {
        const completions = getSpecialAttributeCompletions();
        const keyAttr = completions.find((c) => c.label === ':key');

        expect(keyAttr).toBeDefined();
        expect(keyAttr?.label).toBe(':key');
        expect(keyAttr?.detail).toBe('Efficient diffing for :for loops');

        const doc = (keyAttr?.documentation as any).value;

        // Should explain why it's needed
        expect(doc).toContain('Why Use :key');
        expect(doc).toContain('diffing');

        // Should cover use cases
        expect(doc).toContain('Basic Usage');
        expect(doc).toContain('Pattern Matching');
        expect(doc).toContain('Composite Keys');
        expect(doc).toContain('Preserving Input State');

        // Should show performance impact
        expect(doc).toContain('Performance Impact');
        expect(doc).toContain('1000 items');

        // Should mention best practices
        expect(doc).toContain('Best Practices');
        expect(doc).toContain('unique identifiers');
      });

      it('should have correct insert text snippet', () => {
        const completions = getSpecialAttributeCompletions();
        const keyAttr = completions.find((c) => c.label === ':key');

        expect(keyAttr?.insertText).toContain(':key=');
        expect(keyAttr?.insertText).toContain('.id'); // Common pattern
        expect(keyAttr?.insertText).toContain('${'); // Snippet placeholder
      });
    });

    describe('completion item structure', () => {
      it('should have required completion item properties', () => {
        const completions = getSpecialAttributeCompletions();

        completions.forEach((completion) => {
          // Required properties
          expect(completion).toHaveProperty('label');
          expect(completion).toHaveProperty('kind');
          expect(completion).toHaveProperty('detail');
          expect(completion).toHaveProperty('documentation');
          expect(completion).toHaveProperty('insertTextFormat');
          expect(completion).toHaveProperty('sortText');
          expect(completion).toHaveProperty('filterText');

          // Types
          expect(typeof completion.label).toBe('string');
          expect(typeof completion.detail).toBe('string');
          expect(typeof completion.sortText).toBe('string');
          expect(typeof completion.filterText).toBe('string');

          // Kind should be Property
          expect(completion.kind).toBe(CompletionItemKind.Property);
        });
      });

      it('should have correct sort order', () => {
        const completions = getSpecialAttributeCompletions();

        // All should start with !65 prefix (after Phoenix attrs, before HTML attrs)
        completions.forEach((completion) => {
          expect(completion.sortText).toMatch(/^!65\d{2}$/);
        });

        // Should be in order: :for, :if, :let, :key
        expect(completions[0].label).toBe(':for');
        expect(completions[1].label).toBe(':if');
        expect(completions[2].label).toBe(':let');
        expect(completions[3].label).toBe(':key');
      });
    });

    describe('documentation quality', () => {
      it('should have consistent documentation structure', () => {
        const completions = getSpecialAttributeCompletions();

        completions.forEach((completion) => {
          const doc = (completion.documentation as any).value;

          // Should have sections with bold headers
          expect(doc).toMatch(/\*\*[A-Z]/); // Bold headers

          // Should have code blocks
          expect(doc).toContain('```heex');

          // Should have proper closing of code blocks
          const openBlocks = (doc.match(/```/g) || []).length;
          expect(openBlocks % 2).toBe(0); // Even number (open and close)
        });
      });

      it('should have realistic code examples', () => {
        const completions = getSpecialAttributeCompletions();

        completions.forEach((completion) => {
          const doc = (completion.documentation as any).value;

          // Examples should use proper HEEx syntax
          if (doc.includes('```heex')) {
            // Should have proper attribute syntax
            expect(doc).toMatch(/:(?:for|if|let|key)=/);

            // Should use assigns (@)
            if (completion.label !== ':let') {
              expect(doc).toContain('@');
            }
          }
        });
      });

      it('should reference related concepts', () => {
        const completions = getSpecialAttributeCompletions();
        const forAttr = completions.find((c) => c.label === ':for');
        const keyAttr = completions.find((c) => c.label === ':key');

        const forDoc = (forAttr?.documentation as any).value;
        const keyDoc = (keyAttr?.documentation as any).value;

        // :for should reference :key
        expect(forDoc).toContain(':key');

        // :key should reference :for
        expect(keyDoc).toContain(':for');

        // Should have "See Also" sections
        expect(forDoc).toContain('See Also');
        expect(keyDoc).toContain('See Also');
      });
    });

    describe('enhanced vs old format', () => {
      it('should use object documentation with kind and value', () => {
        const completions = getSpecialAttributeCompletions();

        completions.forEach((completion) => {
          // New format: { kind: MarkupKind.Markdown, value: string }
          expect(completion.documentation).toBeTypeOf('object');
          expect(completion.documentation).toHaveProperty('kind');
          expect(completion.documentation).toHaveProperty('value');

          // Should NOT be a plain string (old format)
          expect(typeof completion.documentation).not.toBe('string');
        });
      });

      it('should have significantly more content than basic docs', () => {
        const completions = getSpecialAttributeCompletions();

        completions.forEach((completion) => {
          const doc = (completion.documentation as any).value;

          // Enhanced docs should be substantial (>500 chars)
          expect(doc.length).toBeGreaterThan(500);

          // Should have multiple sections (indicated by multiple bold headers)
          const boldHeaders = (doc.match(/\*\*[A-Z][^*]+\*\*/g) || []).length;
          expect(boldHeaders).toBeGreaterThan(3);
        });
      });
    });
  });
});
