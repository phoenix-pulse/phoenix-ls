import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { PerfTimer, time } from './utils/perf';
import {
  parseElixirSchemas,
  isSchemaError,
  isElixirAvailable,
  type SchemaMetadata,
  type SchemaInfo as ElixirSchemaInfo,
  type SchemaFieldInfo as ElixirSchemaFieldInfo,
} from './parsers/elixir-ast-parser';

/**
 * Represents a field in an Ecto schema
 */
export interface SchemaField {
  name: string;
  type: string; // :string, :integer, :boolean, :map, etc.
  elixirType?: string; // For embedded_schema or belongs_to (e.g., "User", "Profile")
}

/**
 * Represents an association in an Ecto schema
 */
export interface SchemaAssociation {
  fieldName: string;
  targetModule: string;
  type: string; // "belongs_to", "has_one", "has_many", "many_to_many", "embeds_one", "embeds_many"
}

/**
 * Represents an Ecto schema
 */
export interface EctoSchema {
  moduleName: string; // Full module name (e.g., "MyApp.Accounts.User")
  tableName?: string; // Table name for regular schemas
  fields: SchemaField[];
  associations: Map<string, string>; // field name -> module name (for backwards compatibility)
  associationsDetailed: SchemaAssociation[]; // detailed associations with type info
  aliases: Map<string, string>; // short name -> full name (e.g., "Product" -> "Elodie.Catalog.Product")
  filePath: string;
  line: number;
}

/**
 * Registry for Ecto schemas to support type inference and nested property completion
 */
export class SchemaRegistry {
  private schemas: Map<string, EctoSchema> = new Map(); // moduleName -> schema
  private schemasByFile: Map<string, EctoSchema[]> = new Map(); // filePath -> schemas
  private workspaceRoot: string = '';
  private fileHashes: Map<string, string> = new Map();
  private useElixirParser: boolean = true; // Feature flag: use Elixir AST parser
  private elixirAvailable: boolean | null = null; // Cache Elixir availability check

  constructor() {
    // Check environment variable to disable Elixir parser
    if (process.env.PHOENIX_PULSE_USE_REGEX_PARSER === 'true') {
      this.useElixirParser = false;
    }
  }

  setWorkspaceRoot(root: string) {
    this.workspaceRoot = root;
  }

  /**
   * Convert Elixir AST parser output to EctoSchema format
   */
  private convertElixirToEctoSchemas(
    metadata: SchemaMetadata,
    filePath: string
  ): EctoSchema[] {
    const schemas: EctoSchema[] = [];

    for (const elixirSchema of metadata.schemas) {
      const fields: SchemaField[] = elixirSchema.fields.map((f) => ({
        name: f.name,
        type: f.type,
        elixirType: f.elixir_type || undefined,
      }));

      // Convert associations array to detailed format
      const associationsDetailed: SchemaAssociation[] = elixirSchema.associations.map((a) => ({
        fieldName: a.field_name,
        targetModule: a.target_module,
        type: a.type,
      }));

      // Also create Map format for backwards compatibility
      const associations = new Map<string, string>();
      for (const assoc of elixirSchema.associations) {
        associations.set(assoc.field_name, assoc.target_module);
      }

      // Convert aliases record to Map
      const aliases = new Map<string, string>(
        Object.entries(metadata.aliases)
      );

      schemas.push({
        moduleName: elixirSchema.module_name,
        tableName: elixirSchema.table_name || undefined,
        fields,
        associations,
        associationsDetailed,
        aliases,
        filePath,
        line: elixirSchema.line,
      });
    }

    return schemas;
  }

  /**
   * Parse a single Elixir file using the Elixir AST parser (with fallback to regex)
   */
  private async parseFileWithElixir(
    filePath: string,
    content: string
  ): Promise<EctoSchema[] | null> {
    // Check if Elixir is available (cache result)
    if (this.elixirAvailable === null) {
      this.elixirAvailable = await isElixirAvailable();
      if (!this.elixirAvailable) {
        console.log('[Phoenix Pulse] Elixir not available - using regex schema parser only');
        this.useElixirParser = false;
      }
    }

    if (!this.useElixirParser || !this.elixirAvailable) {
      return null; // Signal to use regex fallback
    }

    try {
      const result = await parseElixirSchemas(filePath, true);

      if (isSchemaError(result)) {
        return null; // Fall back to regex
      }

      const metadata = result as SchemaMetadata;
      const schemas = this.convertElixirToEctoSchemas(metadata, filePath);

      return schemas;
    } catch (error) {
      return null; // Fall back to regex
    }
  }

  /**
   * Parse a single Elixir file asynchronously (tries Elixir AST parser first)
   */
  async parseFileAsync(filePath: string, content: string): Promise<EctoSchema[]> {
    // Try Elixir parser first
    const elixirSchemas = await this.parseFileWithElixir(filePath, content);

    if (elixirSchemas !== null) {
      return elixirSchemas;
    }

    // Fall back to regex parser
    return this.parseFile(filePath, content);
  }

  /**
   * Parse an Elixir file and extract Ecto schema definitions (synchronous, regex-based)
   */
  parseFile(filePath: string, content: string): EctoSchema[] {
    const timer = new PerfTimer('schemas.parseFile');
    const schemas: EctoSchema[] = [];
    const lines = content.split('\n');

    // Extract module name
    let moduleName = '';
    for (const line of lines) {
      const moduleMatch = /defmodule\s+([\w.]+)\s+do/.exec(line);
      if (moduleMatch) {
        moduleName = moduleMatch[1];
        break;
      }
    }

    if (!moduleName) {
      return schemas;
    }

    // Extract aliases (before schema block)
    // alias Elodie.Catalog.Product
    // alias Elodie.Catalog.Product, as: ProductAlias
    const aliases = new Map<string, string>();
    for (const line of lines) {
      const aliasPattern = /^\s*alias\s+([\w.]+)(?:\s*,\s*as:\s*(\w+))?/;
      const aliasMatch = aliasPattern.exec(line);
      if (aliasMatch) {
        const fullPath = aliasMatch[1];
        const shortName = aliasMatch[2] || fullPath.split('.').pop() || fullPath;
        aliases.set(shortName, fullPath);
      }
    }

    let currentSchema: EctoSchema | null = null;
    let inSchemaBlock = false;
    let schemaDepth = 0;

    lines.forEach((line, index) => {
      const trimmedLine = line.trim();

      // Pattern 1: Detect schema block
      // Match: schema "users" do or embedded_schema do
      const schemaPattern = /^(?:schema\s+["']([^"']+)["']|embedded_schema)\s+do$/;
      const schemaMatch = schemaPattern.exec(trimmedLine);

      if (schemaMatch) {
        inSchemaBlock = true;
        schemaDepth = 1;
        currentSchema = {
          moduleName,
          tableName: schemaMatch[1], // May be undefined for embedded_schema
          fields: [],
          associations: new Map(),
          associationsDetailed: [], // Will be populated when associations are parsed
          aliases: new Map(aliases), // Copy module-level aliases
          filePath,
          line: index + 1,
        };
      }

      // Track do/end depth
      if (inSchemaBlock) {
        if (trimmedLine.match(/\bdo\b/) && !trimmedLine.match(/^(?:schema|embedded_schema)/)) {
          schemaDepth++;
        }
        if (trimmedLine === 'end') {
          schemaDepth--;
          if (schemaDepth === 0) {
            // End of schema block
            inSchemaBlock = false;
            if (currentSchema && currentSchema.fields.length > 0) {
              // Auto-add :id field for regular schemas (not embedded_schema)
              if (currentSchema.tableName && !currentSchema.fields.some(f => f.name === 'id')) {
                currentSchema.fields.unshift({
                  name: 'id',
                  type: 'id',
                });
              }
              schemas.push(currentSchema);
            }
            currentSchema = null;
          }
        }
      }

      if (!inSchemaBlock || !currentSchema) {
        return;
      }

      // Pattern 2: Parse field definitions
      // Match: field :name, :string, default: "value"
      // Match: field :age, :integer
      // Match: field :metadata, :map
      const fieldPattern = /^field\s+:([a-z_][a-z0-9_]*)\s*,\s*:([a-z_]+)/;
      const fieldMatch = fieldPattern.exec(trimmedLine);

      if (fieldMatch) {
        currentSchema.fields.push({
          name: fieldMatch[1],
          type: fieldMatch[2],
        });
        return;
      }

      // Pattern 3: Parse belongs_to associations
      // Match: belongs_to :user, User
      // Match: belongs_to :profile, MyApp.Accounts.Profile
      const belongsToPattern = /^belongs_to\s+:([a-z_][a-z0-9_]*)\s*,\s*([\w.]+)/;
      const belongsToMatch = belongsToPattern.exec(trimmedLine);

      if (belongsToMatch) {
        const fieldName = belongsToMatch[1];
        const associationType = belongsToMatch[2];

        // Resolve module name with priority:
        // 1. Full path (has dots) - use as-is
        // 2. Check aliases map
        // 3. Fall back to same namespace (if module has namespace)
        // 4. Use as-is if single-segment module (e.g., just "User")
        let fullTypeName: string;
        if (associationType.includes('.')) {
          // Already a full path
          fullTypeName = associationType;
        } else if (currentSchema.aliases.has(associationType)) {
          // Found in aliases
          fullTypeName = currentSchema.aliases.get(associationType)!;
        } else {
          // Fall back to same namespace
          const namespace = moduleName.split('.').slice(0, -1).join('.');
          if (namespace) {
            // Module has namespace (e.g., MyApp.Accounts.User)
            fullTypeName = `${namespace}.${associationType}`;
          } else {
            // Single-segment module (e.g., just "User") - use type as-is
            fullTypeName = associationType;
          }
        }

        currentSchema.associations.set(fieldName, fullTypeName);
        currentSchema.fields.push({
          name: fieldName,
          type: 'assoc',
          elixirType: fullTypeName,
        });
        return;
      }

      // Pattern 4: Parse has_one associations
      // Match: has_one :profile, Profile
      const hasOnePattern = /^has_one\s+:([a-z_][a-z0-9_]*)\s*,\s*([\w.]+)/;
      const hasOneMatch = hasOnePattern.exec(trimmedLine);

      if (hasOneMatch) {
        const fieldName = hasOneMatch[1];
        const associationType = hasOneMatch[2];

        // Resolve using same logic as belongs_to (check aliases first)
        let fullTypeName: string;
        if (associationType.includes('.')) {
          fullTypeName = associationType;
        } else if (currentSchema.aliases.has(associationType)) {
          fullTypeName = currentSchema.aliases.get(associationType)!;
        } else {
          const namespace = moduleName.split('.').slice(0, -1).join('.');
          if (namespace) {
            fullTypeName = `${namespace}.${associationType}`;
          } else {
            fullTypeName = associationType;
          }
        }

        currentSchema.associations.set(fieldName, fullTypeName);
        currentSchema.fields.push({
          name: fieldName,
          type: 'assoc',
          elixirType: fullTypeName,
        });
        return;
      }

      // Pattern 5: Parse has_many associations
      // Match: has_many :posts, Post
      const hasManyPattern = /^has_many\s+:([a-z_][a-z0-9_]*)\s*,\s*([\w.]+)/;
      const hasManyMatch = hasManyPattern.exec(trimmedLine);

      if (hasManyMatch) {
        const fieldName = hasManyMatch[1];
        const associationType = hasManyMatch[2];

        // Resolve using same logic as belongs_to (check aliases first)
        let fullTypeName: string;
        if (associationType.includes('.')) {
          fullTypeName = associationType;
        } else if (currentSchema.aliases.has(associationType)) {
          fullTypeName = currentSchema.aliases.get(associationType)!;
        } else {
          const namespace = moduleName.split('.').slice(0, -1).join('.');
          if (namespace) {
            fullTypeName = `${namespace}.${associationType}`;
          } else {
            fullTypeName = associationType;
          }
        }

        currentSchema.associations.set(fieldName, fullTypeName);
        currentSchema.fields.push({
          name: fieldName,
          type: 'list',
          elixirType: fullTypeName,
        });
        return;
      }

      // Pattern 6: Parse embeds_one
      // Match: embeds_one :address, Address
      const embedsOnePattern = /^embeds_one\s+:([a-z_][a-z0-9_]*)\s*,\s*([\w.]+)/;
      const embedsOneMatch = embedsOnePattern.exec(trimmedLine);

      if (embedsOneMatch) {
        const fieldName = embedsOneMatch[1];
        const embedType = embedsOneMatch[2];

        // Resolve using aliases (embedded schemas can also be aliased)
        let fullTypeName: string;
        if (embedType.includes('.')) {
          fullTypeName = embedType;
        } else if (currentSchema.aliases.has(embedType)) {
          fullTypeName = currentSchema.aliases.get(embedType)!;
        } else {
          // Embeds default to current module namespace
          fullTypeName = `${moduleName}.${embedType}`;
        }

        currentSchema.associations.set(fieldName, fullTypeName);
        currentSchema.fields.push({
          name: fieldName,
          type: 'embed',
          elixirType: fullTypeName,
        });
        return;
      }

      // Pattern 7: Parse embeds_many
      // Match: embeds_many :addresses, Address
      const embedsManyPattern = /^embeds_many\s+:([a-z_][a-z0-9_]*)\s*,\s*([\w.]+)/;
      const embedsManyMatch = embedsManyPattern.exec(trimmedLine);

      if (embedsManyMatch) {
        const fieldName = embedsManyMatch[1];
        const embedType = embedsManyMatch[2];

        // Resolve using aliases (embedded schemas can also be aliased)
        let fullTypeName: string;
        if (embedType.includes('.')) {
          fullTypeName = embedType;
        } else if (currentSchema.aliases.has(embedType)) {
          fullTypeName = currentSchema.aliases.get(embedType)!;
        } else {
          // Embeds default to current module namespace
          fullTypeName = `${moduleName}.${embedType}`;
        }

        currentSchema.associations.set(fieldName, fullTypeName);
        currentSchema.fields.push({
          name: fieldName,
          type: 'list',
          elixirType: fullTypeName,
        });
        return;
      }

      // Pattern 8: Parse timestamps() macro
      // Match: timestamps() or timestamps(type: :utc_datetime)
      if (trimmedLine.match(/^timestamps\s*\(/)) {
        // Add inserted_at and updated_at fields
        if (!currentSchema.fields.some(f => f.name === 'inserted_at')) {
          currentSchema.fields.push({
            name: 'inserted_at',
            type: 'naive_datetime',
          });
        }
        if (!currentSchema.fields.some(f => f.name === 'updated_at')) {
          currentSchema.fields.push({
            name: 'updated_at',
            type: 'naive_datetime',
          });
        }
        return;
      }
    });

    // Add automatic ID field for regular schemas (not embedded_schema)
    if (currentSchema && currentSchema.tableName && !currentSchema.fields.some(f => f.name === 'id')) {
      currentSchema.fields.unshift({
        name: 'id',
        type: 'id',
      });
    }

    timer.stop({ file: path.relative(this.workspaceRoot || '', filePath), count: schemas.length });
    return schemas;
  }

  /**
   * Update schemas for a specific file
   */
  /**
   * Update file in registry using async parser (tries Elixir AST first)
   */
  async updateFileAsync(filePath: string, content: string): Promise<void> {
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previousHash = this.fileHashes.get(filePath);

    if (previousHash === hash) {
      return;
    }

    const timer = new PerfTimer('schemas.updateFileAsync');
    const shortPath = path.relative(this.workspaceRoot || '', filePath);

    // STEP 1: Parse the new schemas FIRST (don't modify registry yet)
    const newSchemas = await this.parseFileAsync(filePath, content);

    // STEP 2: Get old schemas we need to remove
    const oldSchemas = this.schemasByFile.get(filePath) || [];

    console.log(`[SchemaRegistry] Updating ${shortPath}: ${oldSchemas.length} old schemas, ${newSchemas.length} new schemas`);
    if (oldSchemas.length > 0) {
      console.log(`[SchemaRegistry]   Removing: ${oldSchemas.map(s => s.moduleName).join(', ')}`);
    }
    if (newSchemas.length > 0) {
      console.log(`[SchemaRegistry]   Adding: ${newSchemas.map(s => s.moduleName).join(', ')}`);
    }

    // STEP 3: Build complete new state FIRST (no race condition)
    // Create new Map with all existing schemas except the old ones from this file
    const newSchemasMap = new Map(this.schemas);

    // Remove old schemas from the new map
    oldSchemas.forEach(schema => {
      newSchemasMap.delete(schema.moduleName);
    });

    // Add new schemas to the new map
    newSchemas.forEach(schema => {
      newSchemasMap.set(schema.moduleName, schema);
      console.log(`[SchemaRegistry] Found schema ${schema.moduleName} with ${schema.fields.length} fields`);
    });

    // STEP 4: Atomic swap - single assignment, no race window
    this.schemas = newSchemasMap;

    // STEP 5: Update secondary indexes
    if (newSchemas.length > 0) {
      this.schemasByFile.set(filePath, newSchemas);
      this.fileHashes.set(filePath, hash);
    } else {
      this.schemasByFile.delete(filePath);
      this.fileHashes.delete(filePath);
    }

    timer.stop({ file: shortPath, schemas: newSchemas.length });
  }

  /**
   * Update file in registry (synchronous, uses regex parser)
   */
  updateFile(filePath: string, content: string) {
    const hash = crypto.createHash('sha1').update(content).digest('hex');
    const previousHash = this.fileHashes.get(filePath);

    if (previousHash === hash) {
      return;
    }

    const timer = new PerfTimer('schemas.updateFile');
    const shortPath = path.relative(this.workspaceRoot || '', filePath);

    // STEP 1: Parse the new schemas FIRST (don't modify registry yet)
    const newSchemas = this.parseFile(filePath, content);

    // STEP 2: Get old schemas we need to remove
    const oldSchemas = this.schemasByFile.get(filePath) || [];

    console.log(`[SchemaRegistry] Updating ${shortPath}: ${oldSchemas.length} old schemas, ${newSchemas.length} new schemas`);
    if (oldSchemas.length > 0) {
      console.log(`[SchemaRegistry]   Removing: ${oldSchemas.map(s => s.moduleName).join(', ')}`);
    }
    if (newSchemas.length > 0) {
      console.log(`[SchemaRegistry]   Adding: ${newSchemas.map(s => s.moduleName).join(', ')}`);
    }

    // STEP 3: Build complete new state FIRST (no race condition)
    // Create new Map with all existing schemas except the old ones from this file
    const newSchemasMap = new Map(this.schemas);

    // Remove old schemas from the new map
    oldSchemas.forEach(schema => {
      newSchemasMap.delete(schema.moduleName);
    });

    // Add new schemas to the new map
    newSchemas.forEach(schema => {
      newSchemasMap.set(schema.moduleName, schema);
      console.log(`[SchemaRegistry] Found schema ${schema.moduleName} with ${schema.fields.length} fields`);
    });

    // STEP 4: Atomic swap - single assignment, no race window
    this.schemas = newSchemasMap;

    // STEP 5: Update secondary indexes
    if (newSchemas.length > 0) {
      this.schemasByFile.set(filePath, newSchemas);
      this.fileHashes.set(filePath, hash);
    } else {
      this.schemasByFile.delete(filePath);
      this.fileHashes.delete(filePath);
    }

    timer.stop({ file: shortPath, schemas: newSchemas.length });
  }

  /**
   * Remove a file from the registry
   */
  removeFile(filePath: string) {
    const schemas = this.schemasByFile.get(filePath) || [];
    schemas.forEach(schema => {
      this.schemas.delete(schema.moduleName);
    });
    this.schemasByFile.delete(filePath);
    this.fileHashes.delete(filePath);
  }

  /**
   * Get a schema by module name
   */
  getSchema(moduleName: string): EctoSchema | null {
    return this.schemas.get(moduleName) || null;
  }

  /**
   * Get all schemas
   */
  getAllSchemas(): EctoSchema[] {
    return Array.from(this.schemas.values());
  }

  /**
   * Resolve a type name to a module name
   * Handles both short names (User) and full names (MyApp.Accounts.User)
   */
  resolveTypeName(typeName: string, contextModule?: string): string | null {
    // If it's already a full module name and exists, return it
    if (this.schemas.has(typeName)) {
      return typeName;
    }

    // Try with context module prefix
    if (contextModule) {
      const contextParts = contextModule.split('.');
      // Try same namespace
      const sameNamespace = `${contextParts.slice(0, -1).join('.')}.${typeName}`;
      if (this.schemas.has(sameNamespace)) {
        return sameNamespace;
      }
    }

    // Search for any schema with matching last part
    for (const moduleName of this.schemas.keys()) {
      if (moduleName.endsWith(`.${typeName}`) || moduleName === typeName) {
        return moduleName;
      }
    }

    return null;
  }

  /**
   * Get fields for a nested property path
   * Example: "user.profile.address" -> returns fields for Address schema
   *
   * @param baseType - The base type module name (e.g., "MyApp.Accounts.User")
   * @param path - The property path (e.g., ["profile", "address"])
   * @returns Fields for the final type in the path
   */
  getFieldsForPath(baseType: string, path: string[]): SchemaField[] {
    let currentType = baseType;

    for (const prop of path) {
      const schema = this.getSchema(currentType);
      if (!schema) {
        return [];
      }

      // Find the field
      const field = schema.fields.find(f => f.name === prop);
      if (!field || !field.elixirType) {
        return [];
      }

      // Move to the next type
      const resolvedType = this.resolveTypeName(field.elixirType, currentType);
      if (!resolvedType) {
        return [];
      }
      currentType = resolvedType;
    }

    // Return fields for the final type
    const finalSchema = this.getSchema(currentType);
    return finalSchema ? finalSchema.fields : [];
  }

  /**
   * Scan workspace for schema files
   */
  async scanWorkspace(workspaceRoot: string): Promise<void> {
    this.workspaceRoot = workspaceRoot;

    const filesToScan: Array<{ path: string; content: string }> = [];

    const scanDirectory = (dir: string) => {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);

          // Skip common excluded directories
          if (entry.isDirectory()) {
            const dirName = entry.name;
            if (
              dirName === 'node_modules' ||
              dirName === 'deps' ||
              dirName === '_build' ||
              dirName === '.git' ||
              dirName === 'assets' ||
              dirName === 'priv'
            ) {
              continue;
            }
            scanDirectory(fullPath);
          } else if (entry.isFile() && entry.name.endsWith('.ex')) {
            // Scan all .ex files in lib/ directory for schema definitions
            // Performance is fine because we do a quick string check before parsing
            // Normalize path for cross-platform compatibility (Windows uses backslashes)
            const normalizedPath = fullPath.replace(/\\/g, '/');
            if (normalizedPath.includes('/lib/')) {
              try {
                const content = fs.readFileSync(fullPath, 'utf-8');
                // Quick check if file contains schema definition
                if (content.includes('schema ') || content.includes('embedded_schema')) {
                  filesToScan.push({ path: fullPath, content });
                }
              } catch (err) {
                // Ignore files we can't read
              }
            }
          }
        }
      } catch (err) {
        // Ignore directories we can't read
      }
    };

    // First, collect all files to scan
    time('schemas.scanWorkspace.collect', () => scanDirectory(workspaceRoot), { root: workspaceRoot });

    // Then parse them asynchronously (uses Elixir parser with fallback)
    for (const file of filesToScan) {
      await this.updateFileAsync(file.path, file.content);
    }
  }

  /**
   * Get association information for hover display
   * Returns information about the association type and available fields
   */
  getAssociationInfoFromPath(
    componentsRegistry: any,
    controllersRegistry: any,
    filePath: string,
    baseAssign: string,
    pathSegments: string[],
    offset: number,
    text: string
  ): { associationType: string; targetModule: string; fields: string[] } | null {
    // This is a simplified implementation
    // You would need to:
    // 1. Find the schema for baseAssign (from controller/component attrs)
    // 2. Walk the path through associations
    // 3. Return info about the final association

    // For now, let's implement a basic version that gets the first level
    // First, try to find what type baseAssign is
    // This requires integration with components-registry or controllers-registry

    // Placeholder implementation - you'll need to enhance this based on your existing logic
    // in assigns.ts where you already do this type of path walking

    // Try to get nested fields using existing logic (similar to what's in completions/assigns.ts)
    const baseTypeName = this.inferTypeFromAssign(componentsRegistry, controllersRegistry, filePath, baseAssign, offset, text);

    if (!baseTypeName) {
      return null;
    }

    // Walk through the path
    let currentSchema = this.getSchema(baseTypeName);
    if (!currentSchema) {
      return null;
    }

    // Walk through all but the last segment
    for (let i = 0; i < pathSegments.length - 1; i++) {
      const segment = pathSegments[i];
      const associationModule = currentSchema.associations.get(segment);

      if (!associationModule) {
        return null; // Path doesn't exist
      }

      currentSchema = this.getSchema(associationModule);
      if (!currentSchema) {
        return null; // Schema not found
      }
    }

    // Now get info about the final segment
    const finalSegment = pathSegments[pathSegments.length - 1];
    const targetModule = currentSchema.associations.get(finalSegment);

    if (!targetModule) {
      return null; // Not an association
    }

    const targetSchema = this.getSchema(targetModule);
    if (!targetSchema) {
      return null;
    }

    // Determine association type by checking the field type
    const field = currentSchema.fields.find(f => f.name === finalSegment);
    let associationType = 'Association';

    if (field) {
      if (field.type === 'list') {
        associationType = 'has_many';
      } else if (field.type === 'embed') {
        associationType = 'embeds_one';
      } else if (field.elixirType) {
        associationType = 'belongs_to'; // Most common for singular associations
      }
    }

    // Get available fields from target schema
    const fields = targetSchema.fields.map(f => f.name);

    return {
      associationType,
      targetModule,
      fields,
    };
  }

  /**
   * Helper to infer type from assign name
   * Uses the shared type inference utility
   */
  private inferTypeFromAssign(
    componentsRegistry: any,
    controllersRegistry: any,
    filePath: string,
    assignName: string,
    offset: number,
    text: string
  ): string | null {
    // Import at runtime to avoid circular dependency
    const { inferAssignType } = require('./utils/type-inference');

    return inferAssignType(
      componentsRegistry,
      controllersRegistry,
      this, // schemaRegistry
      filePath,
      assignName,
      offset,
      text
    );
  }

  /**
   * Serialize registry data for caching
   */
  serializeForCache(): any {
    const schemasArray: Array<[string, EctoSchema]> = this.schemas ? Array.from(this.schemas.entries()) : [];
    const schemasByFileArray: Array<[string, EctoSchema[]]> = this.schemasByFile ? Array.from(this.schemasByFile.entries()) : [];
    const fileHashesObj: Record<string, string> = {};

    if (this.fileHashes) {
      for (const [filePath, hash] of this.fileHashes.entries()) {
        fileHashesObj[filePath] = hash;
      }
    }

    return {
      schemas: schemasArray,
      schemasByFile: schemasByFileArray,
      fileHashes: fileHashesObj,
      workspaceRoot: this.workspaceRoot,
    };
  }

  /**
   * Deserialize registry data from cache
   */
  loadFromCache(cacheData: any): void {
    if (!cacheData) {
      return;
    }

    // Clear current data
    if (this.schemas) this.schemas.clear();
    if (this.schemasByFile) this.schemasByFile.clear();
    if (this.fileHashes) this.fileHashes.clear();

    // Load schemas
    if (cacheData.schemas && Array.isArray(cacheData.schemas)) {
      for (const [key, schema] of cacheData.schemas) {
        this.schemas.set(key, schema);
      }
    }

    // Load schemasByFile
    if (cacheData.schemasByFile && Array.isArray(cacheData.schemasByFile)) {
      for (const [filePath, schemas] of cacheData.schemasByFile) {
        this.schemasByFile.set(filePath, schemas);
      }
    }

    // Load file hashes
    if (cacheData.fileHashes) {
      for (const [filePath, hash] of Object.entries(cacheData.fileHashes)) {
        this.fileHashes.set(filePath, hash as string);
      }
    }

    // Load workspace root
    if (cacheData.workspaceRoot) {
      this.workspaceRoot = cacheData.workspaceRoot;
    }

    console.log(`[SchemaRegistry] Loaded ${this.schemas.size} schemas from cache`);
  }
}
