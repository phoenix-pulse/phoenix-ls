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

  it('navigates schema associations to association source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listSchemas') {
          return [
            {
              name: 'App.Catalog.Product',
              tableName: 'products',
              filePath: '/workspace/lib/app/catalog/product.ex',
              location: { line: 10, character: 2 },
              fieldsCount: 0,
              associationsCount: 1,
              fields: [],
              associations: [
                {
                  fieldName: 'category',
                  targetModule: 'App.Catalog.Category',
                  type: 'belongs_to',
                  filePath: '/workspace/lib/app/catalog/product.ex',
                  location: { line: 18, character: 6 }
                }
              ]
            },
            {
              name: 'App.Catalog.Category',
              tableName: 'categories',
              filePath: '/workspace/lib/app/catalog/category.ex',
              location: { line: 4, character: 2 },
              fieldsCount: 0,
              associationsCount: 0,
              fields: [],
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
    const product = schemas.find(item => item.label === 'App.Catalog.Product');
    const sections = await provider.getChildren(product);
    const associationsSection = sections.find(item => item.label === 'Associations');
    const associations = await provider.getChildren(associationsSection);

    expect(associations[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app/catalog/product.ex', { line: 18, character: 6 }]
    });
  });

  it('shows ERD association metadata in association tooltips', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listSchemas') {
          return [
            {
              name: 'App.Catalog.Product',
              tableName: 'products',
              filePath: '/workspace/lib/app/catalog/product.ex',
              location: { line: 10, character: 2 },
              fieldsCount: 0,
              associationsCount: 1,
              fields: [],
              associations: [
                {
                  fieldName: 'tags',
                  targetModule: 'App.Catalog.Tag',
                  type: 'many_to_many',
                  joinThrough: 'products_tags',
                  joinKeys: '[product_id: :id, tag_id: :id]',
                  onReplace: 'delete',
                  filePath: '/workspace/lib/app/catalog/product.ex',
                  location: { line: 18, character: 6 }
                }
              ]
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
    const associationsSection = sections.find(item => item.label === 'Associations');
    const associations = await provider.getChildren(associationsSection);

    expect(associations[0].tooltip).toContain('Join through: products_tags');
    expect(associations[0].tooltip).toContain('Join keys: [product_id: :id, tag_id: :id]');
    expect(associations[0].tooltip).toContain('On replace: delete');
  });

  it('navigates component attrs and slots to nested source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listComponents') {
          return [
            {
              name: 'button',
              module: 'AppWeb.CoreComponents',
              filePath: '/workspace/lib/app_web/components/core_components.ex',
              location: { line: 20, character: 2 },
              attributesCount: 1,
              slotsCount: 1,
              attributes: [
                {
                  name: 'label',
                  type: 'string',
                  required: true,
                  filePath: '/workspace/lib/app_web/components/core_components.ex',
                  location: { line: 12, character: 2 }
                }
              ],
              slots: [
                {
                  name: 'inner_block',
                  required: false,
                  filePath: '/workspace/lib/app_web/components/core_components.ex',
                  location: { line: 15, character: 2 },
                  attributes: []
                }
              ]
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const componentsCategory = roots.find(item => item.label === 'Components');
    const files = await provider.getChildren(componentsCategory);
    const components = await provider.getChildren(files[0]);
    const children = await provider.getChildren(components[0]);

    expect(components[0].data).toMatchObject({
      module: 'AppWeb.CoreComponents',
      name: 'button'
    });

    expect(children[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/components/core_components.ex', { line: 12, character: 2 }]
    });

    expect(children[1].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/components/core_components.ex', { line: 15, character: 2 }]
    });
  });

  it('navigates component slot attrs to nested source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listComponents') {
          return [
            {
              name: 'table',
              module: 'AppWeb.CoreComponents',
              filePath: '/workspace/lib/app_web/components/core_components.ex',
              location: { line: 20, character: 2 },
              attributesCount: 0,
              slotsCount: 1,
              attributes: [],
              slots: [
                {
                  name: 'col',
                  required: false,
                  filePath: '/workspace/lib/app_web/components/core_components.ex',
                  location: { line: 31, character: 2 },
                  attributes: [
                    {
                      name: 'label',
                      type: 'string',
                      required: true,
                      filePath: '/workspace/lib/app_web/components/core_components.ex',
                      location: { line: 32, character: 4 }
                    }
                  ]
                }
              ]
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const componentsCategory = roots.find(item => item.label === 'Components');
    const files = await provider.getChildren(componentsCategory);
    const components = await provider.getChildren(files[0]);
    const componentChildren = await provider.getChildren(components[0]);
    const slot = componentChildren.find(item => item.label === ':col');
    const slotAttrs = await provider.getChildren(slot);

    expect(slotAttrs[0].label).toBe('label: :string');
    expect(slotAttrs[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/components/core_components.ex', { line: 32, character: 4 }]
    });
  });

  it('shows LiveView assigns and navigates to assign source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listLiveView') {
          return [
            {
              module: 'AppWeb.ProductLive.Index',
              filePath: '/workspace/lib/app_web/live/product_live/index.ex',
              location: { line: 5, character: 2 },
              assigns: [
                {
                  name: 'selected_id',
                  filePath: '/workspace/lib/app_web/live/product_live/index.ex',
                  location: { line: 28, character: 14 }
                }
              ],
              functions: []
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const liveViewCategory = roots.find(item => item.label === 'LiveView');
    const folders = await provider.getChildren(liveViewCategory);
    const modules = await provider.getChildren(folders[0]);
    const children = await provider.getChildren(modules[0]);

    expect(children[0].label).toBe('@selected_id');
    expect(children[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/live/product_live/index.ex', { line: 28, character: 14 }]
    });
  });

  it('navigates LiveView functions to function source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listLiveView') {
          return [
            {
              module: 'AppWeb.ProductLive.Index',
              filePath: '/workspace/lib/app_web/live/product_live/index.ex',
              location: { line: 5, character: 2 },
              assigns: [],
              functions: [
                {
                  name: 'handle_event',
                  type: 'handle_event',
                  eventName: 'save',
                  filePath: '/workspace/lib/app_web/live/product_live/events.ex',
                  location: { line: 48, character: 4 }
                }
              ]
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const liveViewCategory = roots.find(item => item.label === 'LiveView');
    const folders = await provider.getChildren(liveViewCategory);
    const modules = await provider.getChildren(folders[0]);
    const children = await provider.getChildren(modules[0]);

    expect(children[0].label).toBe('save');
    expect(children[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/live/product_live/events.ex', { line: 48, character: 4 }]
    });
  });

  it('stores route payload data for copy commands without parsing labels', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listRoutes') {
          return [
            {
              verb: 'GET',
              path: '/products/:id',
              controller: 'AppWeb.ProductController',
              action: 'show',
              filePath: '/workspace/lib/app_web/router.ex',
              location: { line: 42, character: 4 },
              scopePath: '/'
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const routesCategory = roots.find(item => item.label === 'Routes');
    const scopes = await provider.getChildren(routesCategory);
    const controllers = await provider.getChildren(scopes[0]);
    const routes = await provider.getChildren(controllers[0]);

    expect(routes[0].label).toBe('GET /products/:id');
    expect(routes[0].data).toMatchObject({
      path: '/products/:id',
      verb: 'GET'
    });
  });

  it('shows LiveView events with module context and navigates to event source locations', async () => {
    const client = {
      sendRequest: vi.fn(async method => {
        if (method === 'phoenix/listEvents') {
          return [
            {
              name: 'save',
              type: 'handle_event',
              module: 'AppWeb.ProductLive.Index',
              filePath: '/workspace/lib/app_web/live/product_live/index.ex',
              location: { line: 48, character: 4 }
            }
          ];
        }

        return [];
      })
    };

    const provider = new PhoenixPulseTreeProvider(client as never);
    const roots = await provider.getChildren();
    const eventsCategory = roots.find(item => item.label === 'Events');
    const files = await provider.getChildren(eventsCategory);
    const events = await provider.getChildren(files[0]);

    expect(events[0].label).toBe('save');
    expect(events[0].description).toBe('AppWeb.ProductLive.Index');
    expect(events[0].tooltip).toContain('Module: AppWeb.ProductLive.Index');
    expect(events[0].command).toMatchObject({
      command: 'phoenixPulse.goToItem',
      arguments: ['/workspace/lib/app_web/live/product_live/index.ex', { line: 48, character: 4 }]
    });
  });
});
