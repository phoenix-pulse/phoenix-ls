import * as vscode from 'vscode';
import { LanguageClient } from 'vscode-languageclient/node';

interface SchemaInfo {
  name: string;
  tableName?: string;
  filePath: string;
  location: { line: number; character: number };
  fieldsCount: number;
  associationsCount: number;
  fields: Array<{ name: string; type: string; elixirType?: string }>;
  associations: Array<{ fieldName: string; targetModule: string; type: string }>;
}

interface ComponentInfo {
  name: string;
  filePath: string;
  location: { line: number; character: number };
  attributesCount: number;
  slotsCount: number;
  attributes: Array<{
    name: string;
    type: string;
    required: boolean;
    default?: string;
    values?: string[];
    doc?: string;
    rawType?: string;
  }>;
  slots: Array<{
    name: string;
    required: boolean;
    doc?: string;
    attributes: Array<{
      name: string;
      type: string;
      required: boolean;
      default?: string;
      values?: string[];
      doc?: string;
      rawType?: string;
    }>;
  }>;
}

interface RouteInfo {
  verb: string;
  path: string;
  controller: string;
  action: string;
  filePath: string;
  location: { line: number; character: number };
  pipeline?: string;
  scopePath?: string;
  liveModule?: string;
  liveAction?: string;
}

interface TemplateInfo {
  name: string;
  format: string;
  filePath: string;
  location: { line: number; character: number };
  module: string;
}

interface EventInfo {
  name: string;
  type: string;
  filePath: string;
  location: { line: number; character: number };
}

interface LiveViewInfo {
  module: string;
  filePath: string;
  functions: Array<{
    name: string;
    type: 'mount' | 'handle_event' | 'handle_info' | 'handle_params' | 'render';
    eventName?: string; // For handle_event/handle_info
    location: { line: number; character: number };
  }>;
}

export class PhoenixPulseTreeProvider implements vscode.TreeDataProvider<PhoenixTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<PhoenixTreeItem | undefined | null>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  // Cache data for hierarchical display
  private schemasCache: SchemaInfo[] = [];
  private componentsCache: ComponentInfo[] = [];
  private routesCache: RouteInfo[] = [];
  private templatesCache: TemplateInfo[] = [];
  private eventsCache: EventInfo[] = []; // Keep for backward compat with stats
  private liveViewCache: LiveViewInfo[] = [];

  // Search/filter state
  private searchQuery: string = '';

  constructor(private client: LanguageClient) {}

  setSearchQuery(query: string): void {
    this.searchQuery = query.toLowerCase();
    this._onDidChangeTreeData.fire(undefined);
  }

  clearSearch(): void {
    this.searchQuery = '';
    this._onDidChangeTreeData.fire(undefined);
  }

  getSearchQuery(): string {
    return this.searchQuery;
  }

  private getCollapsibleState(): vscode.TreeItemCollapsibleState {
    // Auto-expand when searching to show results
    if (this.searchQuery) {
      return vscode.TreeItemCollapsibleState.Expanded;
    }
    return vscode.TreeItemCollapsibleState.Collapsed;
  }

  private matchesSearch(text: string): boolean {
    if (!this.searchQuery) return true;

    const normalizedText = text.toLowerCase();
    const searchTerms = this.searchQuery.split(/\s+/).filter(t => t.length > 0);

    // All search terms must match (AND logic)
    return searchTerms.every(term => {
      // Check for word boundaries first (more accurate)
      const wordBoundaryRegex = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'i');
      if (wordBoundaryRegex.test(normalizedText)) {
        return true;
      }
      // Fall back to substring match for paths and non-word characters
      return normalizedText.includes(term);
    });
  }

  refresh(): void {
    // Clear caches and search on refresh
    this.schemasCache = [];
    this.componentsCache = [];
    this.templatesCache = [];
    this.eventsCache = [];
    this.routesCache = [];
    this.searchQuery = ''; // Clear search
    this._onDidChangeTreeData.fire(undefined);
  }

  getTreeItem(element: PhoenixTreeItem): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: PhoenixTreeItem): Promise<PhoenixTreeItem[]> {
    if (!this.client) {
      return [];
    }

    try {
      if (!element) {
        // Root level - show categories
        const categories = [
          {
            label: 'Statistics',
            contextValue: 'category-statistics',
            icon: '$(graph)',
            color: 'charts.orange'
          },
          {
            label: 'Schemas',
            contextValue: 'category-schemas',
            icon: '$(database)',
            color: 'charts.blue'
          },
          {
            label: 'Components',
            contextValue: 'category-components',
            icon: '$(symbol-class)',
            color: 'charts.green'
          },
          {
            label: 'Routes',
            contextValue: 'category-routes',
            icon: '$(link)',
            color: 'charts.purple'
          },
          {
            label: 'Templates',
            contextValue: 'category-templates',
            icon: '$(file-code)',
            color: 'charts.yellow'
          },
          {
            label: 'LiveView',
            contextValue: 'category-liveview',
            icon: '$(pulse)',
            color: 'charts.red'
          }
        ];

        return categories.map(cat => {
          const item = new PhoenixTreeItem(
            cat.label,
            cat.contextValue,
            this.getCollapsibleState(),
            cat.icon,
            cat.color
          );

          // Auto-expand when searching to show results
          return item;
        });
      }

      // Get data based on category or file
      switch (element.contextValue) {
        case 'category-statistics':
          return this.getStatisticsSections();
        case 'stats-overview':
          return this.getOverviewStats();
        case 'stats-routes':
          return this.getRouteStats();
        case 'stats-components':
          return this.getComponentStats();
        case 'stats-schemas':
          return this.getTopSchemas();
        case 'category-schemas':
          return this.getSchemas();
        case 'schema-expandable':
          return this.getSchemaSections(element.data);
        case 'schema-fields-section':
          return this.getSchemaFieldsOnly(element.data);
        case 'schema-associations-section':
          return this.getSchemaAssociationsOnly(element.data);
        case 'category-components':
          return this.getComponentFiles();
        case 'component-file':
          return this.getComponentsInFile(element.data);
        case 'component-expandable':
          return this.getComponentAttributes(element.data);
        case 'category-routes':
          return this.getRouteScopes();
        case 'route-scope':
          return this.getControllersInScope(element.data);
        case 'route-controller':
          return this.getRoutesForController(element.data);
        case 'category-templates':
          return this.getTemplateFiles();
        case 'template-file':
          return this.getTemplatesInFile(element.data);
        case 'category-liveview':
          return this.getLiveViewFolders();
        case 'liveview-folder':
          return this.getLiveViewsInFolder(element.data);
        case 'liveview-module':
          return this.getLiveViewFunctions(element.data);
        default:
          return [];
      }
    } catch (error) {
      console.error('[PhoenixPulse] Error getting tree children:', error);
      return [];
    }
  }

  private async getSchemas(): Promise<PhoenixTreeItem[]> {
    try {
      const schemas: SchemaInfo[] = await this.client.sendRequest('phoenix/listSchemas', {});
      this.schemasCache = schemas;

      // Filter by search query
      const filtered = schemas.filter(schema =>
        this.matchesSearch(schema.name) ||
        this.matchesSearch(schema.tableName || '') ||
        this.matchesSearch(schema.filePath)
      );

      if (this.searchQuery) {
        console.log(`[PhoenixPulse] Search "${this.searchQuery}": Found ${filtered.length}/${schemas.length} schemas`);
      }

      return filtered.map(schema => {
        const item = new PhoenixTreeItem(
          schema.name,
          'schema-expandable',
          this.getCollapsibleState(),
          '$(database)',
          'charts.blue'
        );

        const descParts: string[] = [];
        if (schema.fieldsCount > 0) descParts.push(`${schema.fieldsCount} fields`);
        if (schema.associationsCount > 0) descParts.push(`${schema.associationsCount} associations`);
        item.description = descParts.join(', ');

        item.tooltip = `${schema.name} schema\n${descParts.join('\n')}\n${schema.filePath}`;
        item.data = schema; // Store full schema object for copy commands
        return item;
      });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching schemas:', error);
      return [];
    }
  }

  private getSchemaSections(schemaData: SchemaInfo | string): PhoenixTreeItem[] {
    // Handle both old format (string) and new format (SchemaInfo object)
    const schemaName = typeof schemaData === 'string' ? schemaData : schemaData.name;
    const schema = this.schemasCache.find(s => s.name === schemaName);
    if (!schema) {
      return [];
    }

    const items: PhoenixTreeItem[] = [];

    // Add Fields section if there are fields
    if (schema.fields.length > 0) {
      const fieldsSection = new PhoenixTreeItem(
        'Fields',
        'schema-fields-section',
        this.getCollapsibleState(),
        '$(symbol-field)',
        'charts.purple'
      );
      fieldsSection.description = `${schema.fields.length} fields`;
      fieldsSection.data = schemaName;
      items.push(fieldsSection);
    }

    // Add Associations section if there are associations
    if (schema.associations.length > 0) {
      const assocsSection = new PhoenixTreeItem(
        'Associations',
        'schema-associations-section',
        this.getCollapsibleState(),
        '$(references)',
        'charts.orange'
      );
      assocsSection.description = `${schema.associations.length} associations`;
      assocsSection.data = schemaName;
      items.push(assocsSection);
    }

    return items;
  }

  private getSchemaFieldsOnly(schemaName: string): PhoenixTreeItem[] {
    const schema = this.schemasCache.find(s => s.name === schemaName);
    if (!schema) {
      return [];
    }

    return schema.fields.map(field => {
      const label = `${field.name}: ${field.type}`;
      const item = new PhoenixTreeItem(
        label,
        'schema-field',
        vscode.TreeItemCollapsibleState.None,
        '$(symbol-field)',
        'charts.purple'
      );
      item.description = field.elixirType || '';
      item.tooltip = `Field: ${field.name}\nType: ${field.type}${field.elixirType ? `\nElixir Type: ${field.elixirType}` : ''}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Schema',
        arguments: [schema.filePath, schema.location]
      };
      return item;
    });
  }

  private getSchemaAssociationsOnly(schemaName: string): PhoenixTreeItem[] {
    const schema = this.schemasCache.find(s => s.name === schemaName);
    if (!schema) {
      return [];
    }

    return schema.associations.map(assoc => {
      const label = `${assoc.fieldName} → ${assoc.targetModule}`;
      const item = new PhoenixTreeItem(
        label,
        'schema-association',
        vscode.TreeItemCollapsibleState.None,
        '$(arrow-right)',
        'charts.orange'
      );
      item.description = assoc.type;
      item.tooltip = `Association: ${assoc.fieldName}\nType: ${assoc.type}\nTarget: ${assoc.targetModule}`;

      // Try to find target schema and navigate to it
      const targetSchema = this.schemasCache.find(s => s.name === assoc.targetModule);
      if (targetSchema) {
        item.command = {
          command: 'phoenixPulse.goToItem',
          title: 'Go to Schema',
          arguments: [targetSchema.filePath, targetSchema.location]
        };
      } else {
        // If target not found, navigate to current schema
        item.command = {
          command: 'phoenixPulse.goToItem',
          title: 'Go to Schema',
          arguments: [schema.filePath, schema.location]
        };
      }

      return item;
    });
  }

  private async getComponentFiles(): Promise<PhoenixTreeItem[]> {
    try {
      const components: ComponentInfo[] = await this.client.sendRequest('phoenix/listComponents', {});
      this.componentsCache = components;

      // Filter by search query
      const filtered = components.filter(component =>
        this.matchesSearch(component.name) ||
        this.matchesSearch(component.filePath)
      );

      // Group filtered components by file
      const fileMap = new Map<string, ComponentInfo[]>();
      for (const component of filtered) {
        const fileName = component.filePath.split('/').pop() || component.filePath;
        if (!fileMap.has(fileName)) {
          fileMap.set(fileName, []);
        }
        fileMap.get(fileName)!.push(component);
      }

      // Create file nodes
      return Array.from(fileMap.entries()).map(([fileName, fileComponents]) => {
        const item = new PhoenixTreeItem(
          fileName,
          'component-file',
          this.getCollapsibleState(),
          '$(file-code)',
          'charts.green'
        );
        item.description = `${fileComponents.length} components`;
        item.tooltip = `${fileName}\n${fileComponents.length} components\n${fileComponents[0].filePath}`;
        item.data = fileName; // Store filename for later lookup
        return item;
      });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching components:', error);
      return [];
    }
  }

  private getComponentsInFile(fileName: string): PhoenixTreeItem[] {
    const components = this.componentsCache.filter(c =>
      c.filePath.split('/').pop() === fileName
    );

    return components.map(component => {
      const hasContent = component.attributesCount > 0 || component.slotsCount > 0;

      // Build description
      const descParts: string[] = [];
      if (component.attributesCount > 0) descParts.push(`${component.attributesCount} attrs`);
      if (component.slotsCount > 0) descParts.push(`${component.slotsCount} slots`);
      const description = descParts.join(', ');

      const item = new PhoenixTreeItem(
        component.name,
        hasContent ? 'component-expandable' : 'component',
        hasContent ? this.getCollapsibleState() : vscode.TreeItemCollapsibleState.None,
        '$(symbol-class)',
        'charts.green'
      );
      item.description = description;
      item.tooltip = `${component.name} component\n${description}\n${component.filePath}`;

      if (hasContent) {
        item.data = { fileName, componentName: component.name }; // Store both for lookup
      } else {
        // No attributes/slots - click goes directly to component
        item.command = {
          command: 'phoenixPulse.goToItem',
          title: 'Go to Component',
          arguments: [component.filePath, component.location]
        };
      }

      return item;
    });
  }

  private getComponentAttributes(data: { fileName: string; componentName: string }): PhoenixTreeItem[] {
    const component = this.componentsCache.find(c =>
      c.filePath.split('/').pop() === data.fileName && c.name === data.componentName
    );

    if (!component) {
      return [];
    }

    const items: PhoenixTreeItem[] = [];

    // Add attributes
    component.attributes.forEach(attr => {
      const typeDisplay = attr.rawType || `:${attr.type}`;
      const label = `${attr.name}: ${typeDisplay}`;

      const details: string[] = [];
      if (attr.required) details.push('required');
      if (attr.default) details.push(`default: ${attr.default}`);
      if (attr.values && attr.values.length > 0) {
        details.push(`values: [${attr.values.join(', ')}]`);
      }

      const item = new PhoenixTreeItem(
        label,
        'component-attribute',
        vscode.TreeItemCollapsibleState.None,
        '$(symbol-property)',
        'terminal.ansiCyan'
      );
      item.description = details.length > 0 ? details.join(', ') : '';
      item.tooltip = `Attribute: ${attr.name}\nType: ${typeDisplay}${attr.doc ? `\n\n${attr.doc}` : ''}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Component',
        arguments: [component.filePath, component.location]
      };
      items.push(item);
    });

    // Add slots
    component.slots.forEach(slot => {
      const label = `:${slot.name}`;

      const details: string[] = [];
      if (slot.required) details.push('required');
      if (slot.attributes.length > 0) {
        details.push(`${slot.attributes.length} attrs`);
      }

      const item = new PhoenixTreeItem(
        label,
        'component-slot',
        vscode.TreeItemCollapsibleState.None,
        '$(symbol-interface)',
        'terminal.ansiMagenta'
      );
      item.description = details.length > 0 ? details.join(', ') : 'slot';
      item.tooltip = `Slot: ${slot.name}${slot.doc ? `\n\n${slot.doc}` : ''}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Component',
        arguments: [component.filePath, component.location]
      };
      items.push(item);
    });

    return items;
  }

  private async getRouteScopes(): Promise<PhoenixTreeItem[]> {
    try {
      const routes: RouteInfo[] = await this.client.sendRequest('phoenix/listRoutes', {});
      this.routesCache = routes;

      // Filter by search query
      const filtered = routes.filter(route =>
        this.matchesSearch(route.path) ||
        this.matchesSearch(route.verb) ||
        this.matchesSearch(route.controller || '') ||
        this.matchesSearch(route.liveModule || '') ||
        this.matchesSearch(route.action || '')
      );

      // Group filtered routes by scope path
      const scopeMap = new Map<string, RouteInfo[]>();
      for (const route of filtered) {
        const scope = route.scopePath || '/';
        if (!scopeMap.has(scope)) {
          scopeMap.set(scope, []);
        }
        scopeMap.get(scope)!.push(route);
      }

      // Create scope group nodes
      return Array.from(scopeMap.entries())
        .sort((a, b) => {
          // Sort "/" first, then alphabetically
          if (a[0] === '/') return -1;
          if (b[0] === '/') return 1;
          return a[0].localeCompare(b[0]);
        })
        .map(([scope, scopeRoutes]) => {
          const displayName = scope === '/' ? '/ (Public)' : scope;
          const item = new PhoenixTreeItem(
            displayName,
            'route-scope',
            this.getCollapsibleState(),
            '$(folder)',
            'charts.purple'
          );
          item.description = `${scopeRoutes.length} routes`;
          item.tooltip = `Scope: ${scope}\n${scopeRoutes.length} routes`;
          item.data = scope;
          return item;
        });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching routes:', error);
      return [];
    }
  }

  private getControllersInScope(scopePath: string): PhoenixTreeItem[] {
    // Get all routes in this scope
    const scopeRoutes = this.routesCache.filter(r =>
      (r.scopePath || '/') === scopePath
    );

    // Group by controller
    const controllerMap = new Map<string, RouteInfo[]>();
    for (const route of scopeRoutes) {
      const controller = route.liveModule || route.controller || 'Other';
      if (!controllerMap.has(controller)) {
        controllerMap.set(controller, []);
      }
      controllerMap.get(controller)!.push(route);
    }

    // Create controller nodes
    return Array.from(controllerMap.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([controller, controllerRoutes]) => {
        const item = new PhoenixTreeItem(
          controller,
          'route-controller',
          this.getCollapsibleState(),
          '$(symbol-class)',
          'charts.purple'
        );
        item.description = `${controllerRoutes.length} routes`;
        item.tooltip = `${controller}\n${controllerRoutes.length} routes`;
        item.data = { scope: scopePath, controller: controller };
        return item;
      });
  }

  private getRoutesForController(data: { scope: string; controller: string }): PhoenixTreeItem[] {
    const routes = this.routesCache.filter(r =>
      (r.scopePath || '/') === data.scope &&
      (r.liveModule || r.controller) === data.controller
    );

    return routes.map(route => {
      const label = `${route.verb} ${route.path}`;
      const item = new PhoenixTreeItem(
        label,
        'route',
        vscode.TreeItemCollapsibleState.None,
        this.getRouteIcon(route.verb),
        'charts.purple'
      );

      const target = route.liveModule
        ? `${route.liveModule}.${route.liveAction || 'mount'}`
        : `${route.controller}.${route.action}`;

      item.description = `→ ${target}`;
      item.tooltip = `${route.verb} ${route.path}\n→ ${target}\n${route.filePath}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Route',
        arguments: [route.filePath, route.location]
      };
      return item;
    });
  }

  private async getTemplateFiles(): Promise<PhoenixTreeItem[]> {
    try {
      const templates: TemplateInfo[] = await this.client.sendRequest('phoenix/listTemplates', {});
      this.templatesCache = templates;

      // Filter by search query
      const filtered = templates.filter(template =>
        this.matchesSearch(template.name) ||
        this.matchesSearch(template.module) ||
        this.matchesSearch(template.filePath)
      );

      // Group filtered templates by file
      const fileMap = new Map<string, TemplateInfo[]>();
      for (const template of filtered) {
        const fileName = template.filePath.split('/').pop() || template.filePath;
        if (!fileMap.has(fileName)) {
          fileMap.set(fileName, []);
        }
        fileMap.get(fileName)!.push(template);
      }

      // Create file nodes
      return Array.from(fileMap.entries()).map(([fileName, fileTemplates]) => {
        const item = new PhoenixTreeItem(
          fileName,
          'template-file',
          this.getCollapsibleState(),
          '$(file-code)',
          'charts.yellow'
        );
        item.description = `${fileTemplates.length} templates`;
        item.tooltip = `${fileName}\n${fileTemplates.length} templates\n${fileTemplates[0].filePath}`;
        item.data = fileName;
        return item;
      });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching templates:', error);
      return [];
    }
  }

  private getTemplatesInFile(fileName: string): PhoenixTreeItem[] {
    const templates = this.templatesCache.filter(t =>
      t.filePath.split('/').pop() === fileName
    );

    return templates.map(template => {
      const label = `${template.name}.${template.format}`;
      const item = new PhoenixTreeItem(
        label,
        'template',
        vscode.TreeItemCollapsibleState.None,
        '$(file-code)',
        'charts.yellow'
      );
      item.description = template.module;
      item.tooltip = `${label}\nModule: ${template.module}\n${template.filePath}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Template',
        arguments: [template.filePath, template.location]
      };
      return item;
    });
  }

  private async getEventFiles(): Promise<PhoenixTreeItem[]> {
    try {
      const events: EventInfo[] = await this.client.sendRequest('phoenix/listEvents', {});
      this.eventsCache = events;

      // Filter by search query
      const filtered = events.filter(event =>
        this.matchesSearch(event.name) ||
        this.matchesSearch(event.type) ||
        this.matchesSearch(event.filePath)
      );

      // Group filtered events by file
      const fileMap = new Map<string, EventInfo[]>();
      for (const event of filtered) {
        const fileName = event.filePath.split('/').pop() || event.filePath;
        if (!fileMap.has(fileName)) {
          fileMap.set(fileName, []);
        }
        fileMap.get(fileName)!.push(event);
      }

      // Create file nodes
      return Array.from(fileMap.entries()).map(([fileName, fileEvents]) => {
        const item = new PhoenixTreeItem(
          fileName,
          'event-file',
          this.getCollapsibleState(),
          '$(file-code)',
          'charts.red'
        );
        item.description = `${fileEvents.length} events`;
        item.tooltip = `${fileName}\n${fileEvents.length} events\n${fileEvents[0].filePath}`;
        item.data = fileName;
        return item;
      });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching events:', error);
      return [];
    }
  }

  private getEventsInFile(fileName: string): PhoenixTreeItem[] {
    const events = this.eventsCache.filter(e =>
      e.filePath.split('/').pop() === fileName
    );

    return events.map(event => {
      const item = new PhoenixTreeItem(
        event.name,
        'event',
        vscode.TreeItemCollapsibleState.None,
        '$(zap)',
        'charts.red'
      );
      item.description = event.type;
      item.tooltip = `${event.name} (${event.type})\n${event.filePath}`;
      item.command = {
        command: 'phoenixPulse.goToItem',
        title: 'Go to Event',
        arguments: [event.filePath, event.location]
      };
      return item;
    });
  }

  // LiveView methods
  private async getLiveViewFolders(): Promise<PhoenixTreeItem[]> {
    try {
      const liveViewModules: LiveViewInfo[] = await this.client.sendRequest('phoenix/listLiveView', {});
      this.liveViewCache = liveViewModules;

      // Filter by search query
      const filtered = liveViewModules.filter(module =>
        this.matchesSearch(module.module) ||
        this.matchesSearch(module.filePath) ||
        module.functions.some(fn =>
          this.matchesSearch(fn.name) ||
          this.matchesSearch(fn.type) ||
          (fn.eventName && this.matchesSearch(fn.eventName))
        )
      );

      // Group by LiveView folder (e.g., ProductLive, Admin.ProductLive)
      const folderMap = new Map<string, LiveViewInfo[]>();
      for (const module of filtered) {
        const parts = module.module.split('.');
        // Remove web module (first part) and file name (last part)
        // Everything in between is the folder path
        let folderPath = '';
        if (parts.length > 2) {
          folderPath = parts.slice(1, -1).join('.');
        } else if (parts.length === 2) {
          // Only web module and file name, no intermediate folder
          folderPath = parts[0];
        } else {
          folderPath = module.module;
        }

        if (!folderMap.has(folderPath)) {
          folderMap.set(folderPath, []);
        }
        folderMap.get(folderPath)!.push(module);
      }

      // Create folder nodes
      return Array.from(folderMap.entries())
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([folderPath, modules]) => {
          const item = new PhoenixTreeItem(
            folderPath,
            'liveview-folder',
            this.getCollapsibleState(),
            '$(folder)',
            'charts.red'
          );
          item.description = `${modules.length} LiveViews`;
          item.tooltip = `${folderPath}\n${modules.length} LiveView modules`;
          item.data = folderPath;
          return item;
        });
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching LiveView modules:', error);
      return [];
    }
  }

  private getLiveViewsInFolder(folderPath: string): PhoenixTreeItem[] {
    // Get all modules in this folder
    const modules = this.liveViewCache.filter(module => {
      const parts = module.module.split('.');
      let moduleFolderPath = '';
      if (parts.length > 2) {
        moduleFolderPath = parts.slice(1, -1).join('.');
      } else if (parts.length === 2) {
        moduleFolderPath = parts[0];
      } else {
        moduleFolderPath = module.module;
      }
      return moduleFolderPath === folderPath;
    });

    return modules.map(module => {
      const parts = module.module.split('.');
      const fileName = parts[parts.length - 1]; // Last segment is the file name
      const item = new PhoenixTreeItem(
        fileName,
        'liveview-module',
        this.getCollapsibleState(),
        '$(file-code)',
        'charts.red'
      );
      item.description = `${module.functions.length} functions`;
      item.tooltip = `${module.module}\n${module.functions.length} lifecycle functions\n${module.filePath}`;
      item.data = module.module;
      return item;
    });
  }

  private getLiveViewFunctions(moduleName: string): PhoenixTreeItem[] {
    const module = this.liveViewCache.find(m => m.module === moduleName);
    if (!module) {
      return [];
    }

    // Group functions by type for better organization
    const functionsByType: Record<string, typeof module.functions> = {
      mount: [],
      handle_params: [],
      render: [],
      handle_event: [],
      handle_info: []
    };

    for (const func of module.functions) {
      functionsByType[func.type].push(func);
    }

    const items: PhoenixTreeItem[] = [];

    // Helper to get icon for function type
    const getIconForType = (type: string): string => {
      switch (type) {
        case 'mount': return '$(layers)';
        case 'handle_params': return '$(link)';
        case 'render': return '$(file-code)';
        case 'handle_event': return '$(zap)';
        case 'handle_info': return '$(mail)';
        default: return '$(symbol-function)';
      }
    };

    // Add lifecycle functions first (mount, handle_params, render)
    for (const type of ['mount', 'handle_params', 'render']) {
      const functions = functionsByType[type];
      if (functions.length > 0) {
        for (const func of functions) {
          const item = new PhoenixTreeItem(
            func.name,
            'liveview-function',
            vscode.TreeItemCollapsibleState.None,
            getIconForType(type),
            'charts.blue'
          );
          item.description = type;
          item.tooltip = `${func.name}/? (${type})\n${module.filePath}`;
          item.command = {
            command: 'phoenixPulse.goToItem',
            title: 'Go to Function',
            arguments: [module.filePath, func.location]
          };
          items.push(item);
        }
      }
    }

    // Add event handlers (handle_event, handle_info)
    for (const type of ['handle_event', 'handle_info']) {
      const functions = functionsByType[type];
      if (functions.length > 0) {
        for (const func of functions) {
          const displayName = func.eventName || func.name;
          const item = new PhoenixTreeItem(
            displayName,
            'liveview-function',
            vscode.TreeItemCollapsibleState.None,
            getIconForType(type),
            'charts.red'
          );
          item.description = type;
          item.tooltip = `${displayName} (${type})\n${module.filePath}`;
          item.command = {
            command: 'phoenixPulse.goToItem',
            title: 'Go to Function',
            arguments: [module.filePath, func.location]
          };
          items.push(item);
        }
      }
    }

    return items;
  }

  // Statistics methods
  private async getStatisticsSections(): Promise<PhoenixTreeItem[]> {
    return [
      new PhoenixTreeItem(
        'Overview',
        'stats-overview',
        vscode.TreeItemCollapsibleState.Expanded,
        '$(dashboard)',
        'charts.orange'
      ),
      new PhoenixTreeItem(
        'Route Breakdown',
        'stats-routes',
        this.getCollapsibleState(),
        '$(graph-line)',
        'charts.purple'
      ),
      new PhoenixTreeItem(
        'Component Metrics',
        'stats-components',
        this.getCollapsibleState(),
        '$(pulse)',
        'charts.green'
      ),
      new PhoenixTreeItem(
        'Top Schemas',
        'stats-schemas',
        this.getCollapsibleState(),
        '$(star)',
        'charts.blue'
      )
    ];
  }

  private async getOverviewStats(): Promise<PhoenixTreeItem[]> {
    try {
      // Fetch all data if not cached
      if (this.schemasCache.length === 0) {
        this.schemasCache = await this.client.sendRequest('phoenix/listSchemas', {});
      }
      if (this.componentsCache.length === 0) {
        this.componentsCache = await this.client.sendRequest('phoenix/listComponents', {});
      }
      if (this.routesCache.length === 0) {
        this.routesCache = await this.client.sendRequest('phoenix/listRoutes', {});
      }
      if (this.templatesCache.length === 0) {
        this.templatesCache = await this.client.sendRequest('phoenix/listTemplates', {});
      }
      if (this.eventsCache.length === 0) {
        this.eventsCache = await this.client.sendRequest('phoenix/listEvents', {});
      }

      const totalFields = this.schemasCache.reduce((sum, s) => sum + s.fieldsCount, 0);
      const totalAssocs = this.schemasCache.reduce((sum, s) => sum + s.associationsCount, 0);
      const totalAttrs = this.componentsCache.reduce((sum, c) => sum + c.attributesCount, 0);
      const totalSlots = this.componentsCache.reduce((sum, c) => sum + c.slotsCount, 0);

      // Count unique controllers
      const uniqueControllers = new Set(
        this.routesCache.map(r => r.liveModule || r.controller).filter(c => c)
      ).size;

      // Count unique template modules
      const uniqueModules = new Set(this.templatesCache.map(t => t.module)).size;

      return [
        this.createStatItem(
          `${this.schemasCache.length} Schemas`,
          `${totalFields} fields, ${totalAssocs} associations`,
          '$(database)',
          'charts.blue'
        ),
        this.createStatItem(
          `${this.componentsCache.length} Components`,
          `${totalAttrs} attributes, ${totalSlots} slots`,
          '$(symbol-class)',
          'charts.green'
        ),
        this.createStatItem(
          `${this.routesCache.length} Routes`,
          `${uniqueControllers} controllers`,
          '$(link)',
          'charts.purple'
        ),
        this.createStatItem(
          `${this.templatesCache.length} Templates`,
          `${uniqueModules} modules`,
          '$(file-code)',
          'charts.yellow'
        ),
        this.createStatItem(
          `${this.eventsCache.length} Events`,
          `${this.eventsCache.filter(e => e.type === 'handle_event').length} handle_event`,
          '$(zap)',
          'charts.red'
        )
      ];
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching overview stats:', error);
      return [];
    }
  }

  private async getRouteStats(): Promise<PhoenixTreeItem[]> {
    try {
      if (this.routesCache.length === 0) {
        this.routesCache = await this.client.sendRequest('phoenix/listRoutes', {});
      }

      // Count by verb
      const verbCounts = new Map<string, number>();
      for (const route of this.routesCache) {
        const count = verbCounts.get(route.verb) || 0;
        verbCounts.set(route.verb, count + 1);
      }

      // Sort by count descending
      const sorted = Array.from(verbCounts.entries()).sort((a, b) => b[1] - a[1]);

      return sorted.map(([verb, count]) =>
        this.createStatItem(
          `${verb}:`,
          `${count} routes`,
          '$(arrow-right)',
          'charts.purple'
        )
      );
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching route stats:', error);
      return [];
    }
  }

  private async getComponentStats(): Promise<PhoenixTreeItem[]> {
    try {
      if (this.componentsCache.length === 0) {
        this.componentsCache = await this.client.sendRequest('phoenix/listComponents', {});
      }

      // Categorize by attribute count
      const simple = this.componentsCache.filter(c => c.attributesCount <= 3).length;
      const medium = this.componentsCache.filter(c => c.attributesCount > 3 && c.attributesCount <= 8).length;
      const complex = this.componentsCache.filter(c => c.attributesCount > 8).length;

      return [
        this.createStatItem(
          'Simple (0-3 attrs):',
          `${simple} components`,
          '$(circle-outline)',
          'charts.green'
        ),
        this.createStatItem(
          'Medium (4-8 attrs):',
          `${medium} components`,
          '$(circle-filled)',
          'charts.yellow'
        ),
        this.createStatItem(
          'Complex (9+ attrs):',
          `${complex} components`,
          '$(warning)',
          'charts.red'
        )
      ];
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching component stats:', error);
      return [];
    }
  }

  private async getTopSchemas(): Promise<PhoenixTreeItem[]> {
    try {
      if (this.schemasCache.length === 0) {
        this.schemasCache = await this.client.sendRequest('phoenix/listSchemas', {});
      }

      // Sort by total (fields + associations) descending
      const sorted = [...this.schemasCache]
        .sort((a, b) => {
          const totalA = a.fieldsCount + a.associationsCount;
          const totalB = b.fieldsCount + b.associationsCount;
          return totalB - totalA;
        })
        .slice(0, 5); // Top 5

      return sorted.map(schema =>
        this.createStatItem(
          schema.name,
          `${schema.fieldsCount} fields, ${schema.associationsCount} associations`,
          '$(database)',
          'charts.blue'
        )
      );
    } catch (error) {
      console.error('[PhoenixPulse] Error fetching top schemas:', error);
      return [];
    }
  }

  private createStatItem(
    label: string,
    description: string,
    icon: string,
    color: string
  ): PhoenixTreeItem {
    const item = new PhoenixTreeItem(
      label,
      'stat-item',
      vscode.TreeItemCollapsibleState.None,
      icon,
      color
    );
    item.description = description;
    return item;
  }

  private getRouteIcon(verb: string): string {
    switch (verb.toUpperCase()) {
      case 'GET':
        return '$(arrow-down)';
      case 'POST':
        return '$(add)';
      case 'PUT':
      case 'PATCH':
        return '$(edit)';
      case 'DELETE':
        return '$(trash)';
      default:
        return '$(link)';
    }
  }
}

class PhoenixTreeItem extends vscode.TreeItem {
  public data?: any; // Store additional data for hierarchical nodes

  constructor(
    public readonly label: string,
    public readonly contextValue: string,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    iconPath?: string,
    iconColor?: string
  ) {
    super(label, collapsibleState);

    if (iconPath) {
      const iconId = iconPath.replace('$(', '').replace(')', '');
      if (iconColor) {
        this.iconPath = new vscode.ThemeIcon(iconId, new vscode.ThemeColor(iconColor));
      } else {
        this.iconPath = new vscode.ThemeIcon(iconId);
      }
    }
  }
}
