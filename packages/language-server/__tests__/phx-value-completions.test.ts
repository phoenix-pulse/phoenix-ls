import { describe, it, expect } from 'vitest';
import { getContextAwarePhxValueCompletions } from '../src/completions/phoenix';
import { findEnclosingForLoop } from '../src/utils/for-loop-parser';
import { ComponentsRegistry } from '../src/components-registry';
import { ControllersRegistry } from '../src/controllers-registry';
import { SchemaRegistry } from '../src/schema-registry';

describe('context-aware phx-value completions', () => {
  it('detects :for loop context correctly', () => {
    const text = `
      <div :for={product <- @products}>
        <button phx-click="select" phx-value-id={product.id}>
          {product.name}
        </button>
      </div>
    `;

    const offset = text.indexOf('phx-value-id') + 10;
    const forLoop = findEnclosingForLoop(text, offset);

    // Should detect the :for loop
    expect(forLoop).toBeDefined();
    expect(forLoop?.variable).toBeDefined();
    expect(forLoop?.variable?.name).toBe('product');
    expect(forLoop?.variable?.source).toBe('@products');
  });

  it('does not suggest completions when not inside a :for loop', () => {
    const componentsRegistry = new ComponentsRegistry();
    const controllersRegistry = new ControllersRegistry();
    const schemaRegistry = new SchemaRegistry();

    const text = `
      <button phx-click="select" phx-value-█>
        Select
      </button>
    `;

    const offset = text.indexOf('phx-value-█') + 10;
    const linePrefix = text.substring(0, offset).split('\n').pop() || '';
    const filePath = '/test/template.heex';

    const completions = getContextAwarePhxValueCompletions(
      text,
      offset,
      linePrefix,
      filePath,
      componentsRegistry,
      controllersRegistry,
      schemaRegistry
    );

    // Should return empty array when not in :for loop
    expect(completions).toHaveLength(0);
  });

  it('does not suggest completions when not typing phx-value-', () => {
    const componentsRegistry = new ComponentsRegistry();
    const controllersRegistry = new ControllersRegistry();
    const schemaRegistry = new SchemaRegistry();

    const text = `
      <div :for={product <- @products}>
        <button phx-click="select" class="█">
          {product.name}
        </button>
      </div>
    `;

    const offset = text.indexOf('class="█') + 7;
    const linePrefix = text.substring(0, offset).split('\n').pop() || '';
    const filePath = '/test/template.heex';

    const completions = getContextAwarePhxValueCompletions(
      text,
      offset,
      linePrefix,
      filePath,
      componentsRegistry,
      controllersRegistry,
      schemaRegistry
    );

    // Should return empty array when not typing phx-value-
    expect(completions).toHaveLength(0);
  });
});
