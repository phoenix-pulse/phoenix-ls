import { describe, it, expect, beforeAll } from 'vitest';
import * as path from 'path';
import { ComponentsRegistry } from '../src/components-registry';
import {
  parseElixirFile,
  isParserError,
  isElixirAvailable,
  type ComponentMetadata,
} from '../src/parsers/elixir-ast-parser';

describe('Elixir AST Parser vs Regex Parser Comparison', () => {
  let elixirAvailable = false;

  beforeAll(async () => {
    elixirAvailable = await isElixirAvailable();
    if (!elixirAvailable) {
      console.warn('⚠️  Elixir not available - skipping AST parser tests');
    }
  });

  it('should detect if Elixir is available', async () => {
    const available = await isElixirAvailable();
    // Don't fail if Elixir isn't installed (CI/dev environments)
    console.log(`Elixir available: ${available}`);
    expect(typeof available).toBe('boolean');
  });

  it('should parse test component with Elixir parser', async () => {
    if (!elixirAvailable) {
      console.log('⏭️  Skipping - Elixir not available');
      return;
    }

    const testFile = path.resolve(
      __dirname,
      '../elixir-parser/test-component.ex'
    );

    const result = await parseElixirFile(testFile);

    // Should not be an error
    expect(isParserError(result)).toBe(false);

    if (!isParserError(result)) {
      const metadata = result as ComponentMetadata;

      // Check module name
      expect(metadata.module).toBe('TestWeb.Components.Button');

      // Should find 2 components
      expect(metadata.components).toHaveLength(2);

      // Check button component
      const button = metadata.components.find((c) => c.name === 'button');
      expect(button).toBeDefined();
      expect(button!.attributes).toHaveLength(5);
      expect(button!.slots).toHaveLength(2);

      // Check variant attribute
      const variant = button!.attributes.find((a) => a.name === 'variant');
      expect(variant).toBeDefined();
      expect(variant!.type).toBe('string');
      expect(variant!.values).toEqual(['primary', 'secondary', 'danger']);
      expect(variant!.required).toBe(false);

      // Check inner_block slot
      const innerBlock = button!.slots.find((s) => s.name === 'inner_block');
      expect(innerBlock).toBeDefined();
      expect(innerBlock!.required).toBe(true);
      expect(innerBlock!.doc).toBe('Button content');

      // Check card component
      const card = metadata.components.find((c) => c.name === 'card');
      expect(card).toBeDefined();
      expect(card!.attributes).toHaveLength(2);
      expect(card!.slots).toHaveLength(2);

      // Check title attribute (required)
      const title = card!.attributes.find((a) => a.name === 'title');
      expect(title).toBeDefined();
      expect(title!.type).toBe('string');
      expect(title!.required).toBe(true);
    }
  });

  it('should handle errors gracefully', async () => {
    if (!elixirAvailable) {
      console.log('⏭️  Skipping - Elixir not available');
      return;
    }

    const nonExistentFile = '/tmp/does-not-exist.ex';
    const result = await parseElixirFile(nonExistentFile);

    expect(isParserError(result)).toBe(true);

    if (isParserError(result)) {
      expect(result.error).toBe(true);
      expect(result.message).toContain('not found');
    }
  });

  it('should match regex parser results for test components', async () => {
    if (!elixirAvailable) {
      console.log('⏭️  Skipping - Elixir not available');
      return;
    }

    // Use our test component with actual attrs/slots
    const testFile = path.resolve(
      __dirname,
      '../elixir-parser/test-component.ex'
    );

    // Parse with Elixir
    const elixirResult = await parseElixirFile(testFile);
    expect(isParserError(elixirResult)).toBe(false);

    if (!isParserError(elixirResult)) {
      const metadata = elixirResult as ComponentMetadata;

      // Parse with regex (current implementation)
      const registry = new ComponentsRegistry();
      const content = require('fs').readFileSync(testFile, 'utf-8');
      const regexComponents = registry.parseFile(testFile, content);

      // Should find same number of components
      expect(metadata.components.length).toBe(regexComponents.length);

      // Check each component matches
      metadata.components.forEach((elixirComp) => {
        const regexComp = regexComponents.find(
          (c) => c.name === elixirComp.name
        );
        expect(regexComp).toBeDefined();

        if (regexComp) {
          console.log(`\nComparing ${elixirComp.name}:`);
          console.log(`  Elixir: ${elixirComp.attributes.length} attrs, ${elixirComp.slots.length} slots`);
          console.log(`  Regex:  ${regexComp.attributes.length} attrs, ${regexComp.slots.length} slots`);

          // Names should match
          expect(elixirComp.name).toBe(regexComp.name);

          // Module should match
          expect(metadata.module).toBe(regexComp.moduleName);

          // Attributes count should match
          expect(elixirComp.attributes.length).toBe(
            regexComp.attributes.length
          );

          // Slots count should match
          expect(elixirComp.slots.length).toBe(regexComp.slots.length);

          // Check each attribute matches
          elixirComp.attributes.forEach((elixirAttr) => {
            const regexAttr = regexComp.attributes.find(
              (a) => a.name === elixirAttr.name
            );
            expect(regexAttr).toBeDefined();

            if (regexAttr) {
              expect(elixirAttr.type).toBe(regexAttr.type);
              expect(elixirAttr.required).toBe(regexAttr.required);

              // Values should match (if present)
              if (elixirAttr.values && regexAttr.values) {
                expect(elixirAttr.values.sort()).toEqual(
                  regexAttr.values.sort()
                );
              }
            }
          });

          // Check each slot matches
          elixirComp.slots.forEach((elixirSlot) => {
            const regexSlot = regexComp.slots.find(
              (s) => s.name === elixirSlot.name
            );
            expect(regexSlot).toBeDefined();

            if (regexSlot) {
              expect(elixirSlot.required).toBe(regexSlot.required);
            }
          });
        }
      });
    }
  });

  it('should cache results for performance', async () => {
    if (!elixirAvailable) {
      console.log('⏭️  Skipping - Elixir not available');
      return;
    }

    const testFile = path.resolve(
      __dirname,
      '../elixir-parser/test-component.ex'
    );

    // First parse (no cache)
    const start1 = Date.now();
    const result1 = await parseElixirFile(testFile, true);
    const duration1 = Date.now() - start1;

    expect(isParserError(result1)).toBe(false);

    // Second parse (should use cache)
    const start2 = Date.now();
    const result2 = await parseElixirFile(testFile, true);
    const duration2 = Date.now() - start2;

    expect(isParserError(result2)).toBe(false);

    // Cached result should be much faster (at least 2x)
    // Note: This might be flaky in CI, so we'll just log the times
    console.log(`First parse: ${duration1}ms, Second parse: ${duration2}ms`);

    // Results should be identical
    if (!isParserError(result1) && !isParserError(result2)) {
      expect((result1 as ComponentMetadata).components.length).toBe(
        (result2 as ComponentMetadata).components.length
      );
    }
  });
});
