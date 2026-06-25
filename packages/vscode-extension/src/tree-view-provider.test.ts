import { describe, expect, it, vi } from 'vitest';

vi.mock('vscode', () => {
  class TreeItem {
    public description?: string;
    public tooltip?: string;
    public command?: unknown;
    public contextValue?: string;
    public iconPath?: unknown;

    constructor(
      public readonly label: string,
      public readonly collapsibleState: number
    ) {}
  }

  return {
    EventEmitter: class {
      public event = vi.fn();
      public fire = vi.fn();
    },
    ThemeColor: class {
      constructor(public readonly id: string) {}
    },
    ThemeIcon: class {
      constructor(
        public readonly id: string,
        public readonly color?: unknown
      ) {}
    },
    TreeItem,
    TreeItemCollapsibleState: {
      None: 0,
      Collapsed: 1,
      Expanded: 2
    }
  };
});

import { PhoenixPulseTreeProvider } from './tree-view-provider';

describe('PhoenixPulseTreeProvider', () => {
  it('navigates schema fields to field source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listSchemas') {
          return [
            {
              name: 'App.Catalog.Product',
              tableName: 'products',
              filePath: '/workspace/lib/app/catalog/product.ex',
              location: { line: 10, character: 2 },
              fieldsCount: 1,
              associationsCount: 0,
              fields: [
                {
                  name: 'name',
                  type: 'string',
                  elixirType: ':string',
                  filePath: '/workspace/lib/app/catalog/product.ex',
                  location: { line: 14, character: 6 }
                }
              ],
              associations: []
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const schemasCategory = roots.find(item => item.label === 'Schemas');
    const schemas = await provider.getChildren(schemasCategory);
    const sections = await provider.getChildren(schemas[0]);
    const fieldsSection = sections.find(item => item.label === 'Fields');
    const fields = await provider.getChildren(fieldsSection);

    expect(fields[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app/catalog/product.ex', { line: 14, character: 6 }]
    });
  });
});
