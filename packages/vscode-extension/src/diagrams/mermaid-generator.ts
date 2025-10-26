interface SchemaInfo {
  name: string;
  tableName?: string;
  fields: Array<{ name: string; type: string; elixirType?: string }>;
  associations: Array<{ fieldName: string; targetModule: string; type: string }>;
}

/**
 * Extracts simple name from module path (e.g., "MyApp.Accounts.User" → "User")
 */
function getSimpleName(modulePath: string): string {
  const parts = modulePath.split('.');
  return parts[parts.length - 1];
}

/**
 * Gets display name - prefers table name, falls back to simple module name
 */
function getDisplayName(schema: SchemaInfo): string {
  // Use table name if available (e.g., "bootcamps"), otherwise use simple name
  return schema.tableName || getSimpleName(schema.name);
}

/**
 * Create a mapping from module names to their display names (table names)
 */
function buildNameMapping(schemas: SchemaInfo[]): Map<string, string> {
  const mapping = new Map<string, string>();
  for (const schema of schemas) {
    mapping.set(schema.name, getDisplayName(schema));
  }
  return mapping;
}

/**
 * Converts Phoenix schemas to Mermaid ERD syntax
 */
export function generateMermaidDiagram(schemas: SchemaInfo[]): string {
  if (!schemas || schemas.length === 0) {
    return 'erDiagram\n    NO_SCHEMAS["No schemas found in project"]';
  }

  // Build mapping of module names to table names
  const nameMapping = buildNameMapping(schemas);

  let mermaid = 'erDiagram\n';

  // Generate relationships
  for (const schema of schemas) {
    const sourceName = getDisplayName(schema);

    for (const assoc of schema.associations) {
      // Look up target in mapping, fallback to simple name
      const targetName = nameMapping.get(assoc.targetModule) || getSimpleName(assoc.targetModule);
      const relationship = getRelationshipSymbol(assoc.type);
      const label = assoc.type.replace(/_/g, ' ');

      // Format: SourceSchema relationship TargetSchema : "label"
      mermaid += `    ${sourceName} ${relationship} ${targetName} : "${label}"\n`;
    }
  }

  mermaid += '\n';

  // Generate schema definitions
  for (const schema of schemas) {
    const displayName = getDisplayName(schema);

    // Add comment showing Elixir module
    mermaid += `    %% ${schema.name}\n`;

    // Schema name (using table name)
    mermaid += `    ${displayName} {\n`;

    // Add fields (limit to 8 for readability)
    const fieldsToShow = schema.fields.slice(0, 8);
    for (const field of fieldsToShow) {
      const fieldType = mapElixirTypeToMermaid(field.type);
      const isPK = field.name === 'id';
      const isFK = field.name.endsWith('_id');

      let constraint = '';
      if (isPK) constraint = ' PK';
      else if (isFK) constraint = ' FK';

      mermaid += `        ${fieldType} ${field.name}${constraint}\n`;
    }

    // Add count if more fields
    if (schema.fields.length > 8) {
      mermaid += `        string plus_${schema.fields.length - 8}_more\n`;
    }

    mermaid += `    }\n\n`;
  }

  return mermaid;
}

/**
 * Maps Ecto association types to Mermaid relationship symbols
 */
function getRelationshipSymbol(type: string): string {
  switch (type) {
    case 'has_many':
      return '||--o{';
    case 'has_one':
      return '||--||';
    case 'belongs_to':
      return '}o--||';
    case 'many_to_many':
      return '}o--o{';
    case 'embeds_one':
      return '||--||';
    case 'embeds_many':
      return '||--o{';
    default:
      return '||--||';
  }
}

/**
 * Maps Elixir/Ecto types to Mermaid-compatible types
 */
function mapElixirTypeToMermaid(elixirType: string): string {
  const typeMap: Record<string, string> = {
    'integer': 'int',
    'bigint': 'bigint',
    'string': 'string',
    'text': 'text',
    'boolean': 'bool',
    'date': 'date',
    'time': 'time',
    'datetime': 'datetime',
    'decimal': 'decimal',
    'float': 'float',
    'binary': 'blob',
    'uuid': 'uuid',
    'map': 'json',
    'array': 'array'
  };

  return typeMap[elixirType.toLowerCase()] || 'string';
}
