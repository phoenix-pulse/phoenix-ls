import { describe, it, expect, vi } from 'vitest';

vi.mock('../src/parsers/tree-sitter', () => {
  const startComponent = {
    type: 'start_component',
    startIndex: 0,
    endIndex: 8,
    namedChildren: [] as any[],
    childForFieldName: (name: string) => {
      if (name === 'name' || name === 'component_name') {
        return {
          type: 'component_name',
          startIndex: 1,
          endIndex: 7,
          namedChildren: [] as any[],
          childForFieldName: () => null,
        };
      }
      return null;
    },
  };

  const slotNameNode = {
    type: 'slot_name',
    startIndex: 13,
    endIndex: 16,
    namedChildren: [] as any[],
    childForFieldName: () => null,
  };

  const slotNode = {
    type: 'slot',
    startIndex: 10,
    endIndex: 25,
    namedChildren: [slotNameNode],
    childForFieldName: () => null,
  };

  const endComponent = {
    type: 'end_component',
    startIndex: 26,
    endIndex: 36,
    namedChildren: [] as any[],
    childForFieldName: () => null,
  };

  const componentNode = {
    type: 'component',
    startIndex: 0,
    endIndex: 36,
    namedChildren: [startComponent, slotNode, endComponent],
    childForFieldName: (name: string) => {
      if (name === 'start_component') {
        return startComponent;
      }
      if (name === 'end_component') {
        return endComponent;
      }
      return null;
    },
  };

  const rootNode = {
    type: 'fragment',
    startIndex: 0,
    endIndex: 36,
    namedChildren: [componentNode],
    childForFieldName: () => null,
  };

  return {
    isTreeSitterReady: () => true,
    getHeexTree: () => ({ rootNode }),
    clearTreeCache: () => {},
  };
});

import { collectComponentUsages } from '../src/utils/component-usage';

describe('collectComponentUsages (tree-sitter)', () => {
  it('captures slot metadata when tree-sitter is ready', () => {
    const text = '<.table>\n  <:col />\n</.table>';
    const usages = collectComponentUsages(text, 'table.heex');
    const tableUsage = usages.find(u => u.componentName === 'table');
    expect(tableUsage).toBeTruthy();
    if (!tableUsage) {
      return;
    }
    expect(tableUsage.slots.map(slot => slot.name)).toContain('col');
  });
});
