/**
 * Type inference utilities for Phoenix assigns
 * Uses simple pattern matching to infer types from common Elixir/Phoenix patterns
 */

export interface TypeInfo {
  kind: 'struct' | 'list' | 'string' | 'integer' | 'boolean' | 'map' | 'any' | 'changeset';
  module?: string; // For structs: MyApp.Accounts.User
  innerType?: TypeInfo; // For lists: [User]
}

/**
 * Infer type from variable expression
 * Uses simple pattern matching - 80% accuracy is fine!
 *
 * Examples:
 * - Accounts.get_user!(id) → %User{}
 * - Accounts.list_users() → [%User{}]
 * - %User{} → %User{}
 * - Accounts.change_user(user) → %Ecto.Changeset{}
 */
export function inferTypeFromExpression(expr: string, contextModule?: string): TypeInfo | null {
  const trimmed = expr.trim();

  // Pattern 1: Context.get_*!(id) → Returns struct
  // Accounts.get_user!(id) → User
  // Blog.get_post!(id) → Post
  const getPattern = /([\w.]+)\.get_([a-z_]+)!/;
  const getMatch = trimmed.match(getPattern);
  if (getMatch) {
    const [, module, entity] = getMatch;
    const structName = pascalCase(entity);
    return {
      kind: 'struct',
      module: `${module}.${structName}`,
    };
  }

  // Pattern 2: Context.list_*() → Returns list of structs
  // Accounts.list_users() → [User]
  // Blog.list_posts(filters) → [Post]
  const listPattern = /([\w.]+)\.list_([a-z_]+)/;
  const listMatch = trimmed.match(listPattern);
  if (listMatch) {
    const [, module, entity] = listMatch;
    const structName = pascalCase(singularize(entity));
    return {
      kind: 'list',
      innerType: {
        kind: 'struct',
        module: `${module}.${structName}`,
      },
    };
  }

  // Pattern 3: Struct literal %User{}
  const structPattern = /%([A-Z][\w.]*)\{/;
  const structMatch = trimmed.match(structPattern);
  if (structMatch) {
    return {
      kind: 'struct',
      module: structMatch[1],
    };
  }

  // Pattern 4: Context.change_*() → Returns changeset
  // Accounts.change_user(user) → Ecto.Changeset
  const changePattern = /([\w.]+)\.change_([a-z_]+)/;
  if (changePattern.test(trimmed)) {
    return {
      kind: 'changeset',
      module: 'Ecto.Changeset',
    };
  }

  // Pattern 5: to_form(changeset) → Form struct
  if (trimmed.match(/to_form\s*\(/)) {
    return {
      kind: 'struct',
      module: 'Phoenix.HTML.Form',
    };
  }

  // Pattern 6: List literal []
  if (trimmed === '[]') {
    return {
      kind: 'list',
      innerType: { kind: 'any' },
    };
  }

  // Pattern 7: String literal
  if (trimmed.match(/^["']/)) {
    return { kind: 'string' };
  }

  // Pattern 8: Integer literal
  if (trimmed.match(/^\d+$/)) {
    return { kind: 'integer' };
  }

  // Pattern 9: Boolean literal
  if (trimmed === 'true' || trimmed === 'false') {
    return { kind: 'boolean' };
  }

  // Pattern 10: Map literal %{}
  if (trimmed.match(/^%\{/)) {
    return { kind: 'map' };
  }

  // Pattern 11: Repo.preload(struct, assocs)
  // Keep the base struct type, associations will be loaded
  const preloadPattern = /Repo\.preload\s*\(\s*([^,]+)/;
  const preloadMatch = trimmed.match(preloadPattern);
  if (preloadMatch) {
    // Try to infer the type of the first argument
    return inferTypeFromExpression(preloadMatch[1], contextModule);
  }

  return null;
}

/**
 * Trace variable type through simple assignments
 *
 * Example:
 * user = Accounts.get_user!(id)
 * → Tracks that "user" variable has type User
 */
export function traceVariableType(
  functionBody: string,
  varName: string,
  contextModule?: string
): TypeInfo | null {
  // Simple regex: varName = expression
  // This won't handle all cases (pipeline, pattern matching, etc.)
  // But it will handle the common cases!

  const assignPattern = new RegExp(`\\b${escapeRegex(varName)}\\s*=\\s*([^\\n]+)`);
  const match = functionBody.match(assignPattern);

  if (match) {
    const expression = match[1].trim();
    return inferTypeFromExpression(expression, contextModule);
  }

  return null;
}

/**
 * Convert snake_case to PascalCase
 * user → User
 * blog_post → BlogPost
 * admin_user → AdminUser
 */
function pascalCase(str: string): string {
  return str
    .split('_')
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

/**
 * Simple singularization (handles common cases)
 * users → user
 * posts → post
 * categories → category
 */
function singularize(str: string): string {
  if (str.endsWith('ies')) {
    return str.slice(0, -3) + 'y'; // categories → category
  }
  if (str.endsWith('ses')) {
    return str.slice(0, -2); // addresses → address
  }
  if (str.endsWith('s')) {
    return str.slice(0, -1); // users → user
  }
  return str;
}

/**
 * Escape special regex characters
 */
function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Format type info for display
 */
export function formatTypeInfo(typeInfo: TypeInfo): string {
  switch (typeInfo.kind) {
    case 'struct':
      return `%${typeInfo.module}{}`;
    case 'list':
      if (typeInfo.innerType) {
        return `[${formatTypeInfo(typeInfo.innerType)}]`;
      }
      return '[any]';
    case 'changeset':
      return '%Ecto.Changeset{}';
    case 'string':
      return 'String.t()';
    case 'integer':
      return 'integer()';
    case 'boolean':
      return 'boolean()';
    case 'map':
      return 'map()';
    default:
      return 'any()';
  }
}

/**
 * Infers the Elixir module type for a given assign variable
 *
 * This function looks up assign types from two sources:
 * 1. Component attributes (attr :user, User)
 * 2. Controller assigns (render(conn, :show, user: %User{}))
 *
 * @param componentsRegistry - Registry of Phoenix components
 * @param controllersRegistry - Registry of controllers and templates
 * @param schemaRegistry - Registry of Ecto schemas
 * @param filePath - Current file path
 * @param assignName - Name of the assign variable (e.g., "user", "product")
 * @param offset - Cursor offset in the file
 * @param text - Full file content
 * @returns Module name (e.g., "Elodie.Catalog.Product") or null
 */
export function inferAssignType(
  componentsRegistry: any,
  controllersRegistry: any,
  schemaRegistry: any,
  filePath: string,
  assignName: string,
  offset: number,
  text: string
): string | null {
  // Try component path first (for .ex files with components)
  const component = componentsRegistry.getCurrentComponent(filePath, offset, text);
  if (component) {
    const attr = component.attributes.find((a: any) => a.name === assignName);
    if (attr) {
      // Try attr.type first (e.g., "Event", "Product")
      if (attr.type && attr.type.match(/^[A-Z]/)) {
        const resolved = schemaRegistry.resolveTypeName(attr.type);
        if (resolved) {
          return resolved;
        }
      }

      // Try attr.rawType (e.g., "Elodie.Analytics.Event")
      if (attr.rawType && attr.rawType.match(/^[A-Z]/)) {
        const resolved = schemaRegistry.resolveTypeName(attr.rawType);
        if (resolved) {
          return resolved;
        }
      }

      // Try guessing from assign name (user → User)
      const guessedType = assignName.split('_').map(part =>
        part.charAt(0).toUpperCase() + part.slice(1)
      ).join('');
      const resolved = schemaRegistry.resolveTypeName(guessedType);
      if (resolved) {
        return resolved;
      }
    }
  }

  // Try controller/template path (for .heex templates)
  const templateSummary = controllersRegistry.getTemplateSummary(filePath);
  if (templateSummary) {
    const sources = templateSummary.assignSources.get(assignName);
    if (sources && sources.length > 0) {
      // Look for type info in sources
      for (const source of sources) {
        if (source.assignsWithTypes) {
          const assignInfo = source.assignsWithTypes.find((a: any) => a.name === assignName);
          if (assignInfo?.typeInfo) {
            // Handle struct types (%User{})
            if (assignInfo.typeInfo.kind === 'struct' && assignInfo.typeInfo.module) {
              return assignInfo.typeInfo.module;
            }

            // Handle list types ([%User{}])
            if (assignInfo.typeInfo.kind === 'list' && assignInfo.typeInfo.innerType?.module) {
              return assignInfo.typeInfo.innerType.module;
            }
          }
        }
      }
    }
  }

  return null;
}

/**
 * Checks if a variable name is a loop variable (from :for={var <- ...})
 * by looking for :for loops in the surrounding context
 *
 * @param text - Full file content
 * @param offset - Current cursor position
 * @param varName - Variable name to check
 * @returns true if varName is a loop variable in scope
 */
export function isForLoopVariable(text: string, offset: number, varName: string): boolean {
  // Look backwards for :for loops (within ~500 chars)
  const searchStart = Math.max(0, offset - 500);
  const searchText = text.substring(searchStart, offset + 100);

  // Match :for={varName <- ...} patterns
  const forPattern = new RegExp(`:for\\s*=\\s*\\{\\s*${escapeRegex(varName)}\\s*<-`, 'g');
  return forPattern.test(searchText);
}
