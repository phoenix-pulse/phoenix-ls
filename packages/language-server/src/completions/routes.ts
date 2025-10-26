import * as path from 'path';
import { CompletionItem, CompletionItemKind, InsertTextFormat, MarkupKind, TextEdit } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { RouterRegistry } from '../router-registry';

export function getVerifiedRouteCompletions(
  document: TextDocument,
  position: { line: number; character: number },
  linePrefix: string,
  routerRegistry: RouterRegistry
): CompletionItem[] | null {
  // Try matching incomplete string first (when typing new route)
  const incompleteMatch = /~p\"([^"]*)$/.exec(linePrefix);

  // Try matching inside existing string (when editing)
  const line = document.getText({
    start: { line: position.line, character: 0 },
    end: { line: position.line, character: 999 }
  });

  let partial: string | null = null;
  let startCharacter = 0;
  let endCharacter = position.character;

  if (incompleteMatch) {
    // Typing new route: ~p"/raf█ (no closing quote)
    partial = incompleteMatch[1];
    startCharacter = position.character - partial.length;
  } else {
    // Editing existing route: ~p"/raf█fles" (has closing quote)
    // Find the ~p" before cursor
    const beforeCursor = line.substring(0, position.character);
    const lastOpenIndex = beforeCursor.lastIndexOf('~p"');

    if (lastOpenIndex === -1) {
      return null;
    }

    // Find the closing " after the opening ~p"
    const afterOpen = line.substring(lastOpenIndex + 3); // Skip ~p"
    const closeIndex = afterOpen.indexOf('"');

    if (closeIndex === -1) {
      return null;
    }

    // Check if cursor is between ~p" and "
    const openPos = lastOpenIndex + 3;
    const closePos = lastOpenIndex + 3 + closeIndex;

    if (position.character < openPos || position.character > closePos) {
      return null;
    }

    // Extract partial from opening quote to cursor
    partial = line.substring(openPos, position.character);
    startCharacter = openPos;
    endCharacter = closePos;
  }

  if (!partial) {
    return null;
  }

  const routes = routerRegistry.getRoutes();
  console.log(`[getVerifiedRouteCompletions] Requested, found ${routes.length} routes`);
  if (routes.length === 0) {
    return null;
  }

  // Strip query strings and interpolations for matching
  // "/raffles?#{params}" -> "/raffles"
  // "/users/#{id}" -> "/users/"
  const partialForMatching = partial.split('?')[0].split('#')[0];
  console.log(`[getVerifiedRouteCompletions] Partial: "${partial}", matching: "${partialForMatching}"`);

  const range = {
    start: { line: position.line, character: startCharacter },
    end: { line: position.line, character: endCharacter },
  };

  return routes
    .filter(route => route.path.startsWith('/') && route.path.startsWith(partialForMatching, 0))
    .map((route, index) => ({
      label: route.path,
      kind: CompletionItemKind.Value,
      detail: `${route.verb} ${route.path}`,
      documentation: `Route defined in ${path.basename(route.filePath)} (line ${route.line})`,
      textEdit: TextEdit.replace(range, route.path),
      sortText: `!0${index.toString().padStart(3, '0')}`,
    }));
}

interface HelperGroup {
  helperBase: string;
  actions: Set<string>;
  params: Set<string>;
  verbs: Set<string>;
  paths: Set<string>;
  controllers: Set<string>;
  files: Set<string>;
  isResource: boolean;
}

function sortUnique(values: Set<string>): string[] {
  return Array.from(values).filter(Boolean).sort((a, b) => a.localeCompare(b));
}

function buildActionChoices(group: HelperGroup, routerRegistry: RouterRegistry): string[] {
  const actions = sortUnique(group.actions);
  if (group.isResource) {
    // Use the router registry to get valid actions based on only:/except: options
    const validActions = routerRegistry.getValidResourceActions(group.helperBase);
    if (validActions.length > 0) {
      return validActions;
    }
    // Fallback to default actions
    return actions.length > 0 ? actions : ['index', 'new', 'create', 'show', 'edit', 'update', 'delete'];
  }
  return actions;
}

function buildSnippet(helperBase: string, variant: 'path' | 'url', group: HelperGroup, routerRegistry: RouterRegistry): string {
  const helperName = `${helperBase}_${variant}`;
  let placeholderIndex = 1;
  const args: string[] = [];

  args.push(`\${${placeholderIndex++}:conn_or_socket}`);

  const actionChoices = buildActionChoices(group, routerRegistry);
  if (actionChoices.length > 0) {
    if (actionChoices.length === 1) {
      args.push(`:\${${placeholderIndex++}:${actionChoices[0]}}`);
    } else {
      args.push(`:\${${placeholderIndex++}|${actionChoices.join(',')}|}`);
    }
  }

  const params = sortUnique(group.params);
  params.forEach(param => {
    args.push(`\${${placeholderIndex++}:${param || 'param'}}`);
  });

  if (args.length === 0) {
    return helperName;
  }

  return `${helperName}(${args.join(', ')})`;
}

function buildHelperDocumentation(helperBase: string, variant: 'path' | 'url', group: HelperGroup, routerRegistry: RouterRegistry): string {
  const helperName = `Routes.${helperBase}_${variant}`;
  const lines: string[] = [];

  lines.push(`**${helperName}**`);

  const verbs = sortUnique(group.verbs);
  const paths = sortUnique(group.paths);
  const actions = buildActionChoices(group, routerRegistry);
  const params = sortUnique(group.params);
  const controllers = sortUnique(group.controllers);
  const files = sortUnique(group.files);

  if (verbs.length > 0) {
    lines.push(``, `- Verbs: ${verbs.join(', ')}`);
  }

  if (paths.length > 0) {
    lines.push(`- Paths:`);
    paths.forEach(pathValue => {
      lines.push(`  - \`${pathValue}\``);
    });
  }

  if (actions.length > 0) {
    lines.push(`- Actions: ${actions.map(action => `\`:${action}\``).join(', ')}`);
  }

  if (params.length > 0) {
    lines.push(`- Params: ${params.map(param => `\`${param}\``).join(', ')}`);
  }

  if (controllers.length > 0) {
    lines.push(`- Controllers: ${controllers.map(controller => `\`${controller}\``).join(', ')}`);
  }

  if (files.length > 0) {
    lines.push(`- Defined in: ${files.join(', ')}`);
  }

  return lines.join('\n');
}

export function getRouteHelperCompletions(
  document: TextDocument,
  position: { line: number; character: number },
  linePrefix: string,
  routerRegistry: RouterRegistry
): CompletionItem[] | null {
  const match = /Routes\.([A-Za-z0-9_]*)$/.exec(linePrefix);
  if (!match) {
    return null;
  }

  const partial = match[1] ?? '';
  const startCharacter = position.character - partial.length;
  const range = {
    start: { line: position.line, character: startCharacter },
    end: position,
  };

  const routes = routerRegistry.getRoutes();
  if (routes.length === 0) {
    return null;
  }

  const helperMap = new Map<string, HelperGroup>();

  routes.forEach(route => {
    if (!route.helperBase || route.verb === 'FORWARD') {
      return;
    }

    const key = route.helperBase;
    let entry = helperMap.get(key);
    if (!entry) {
      entry = {
        helperBase: route.helperBase,
        actions: new Set<string>(),
        params: new Set<string>(),
        verbs: new Set<string>(),
        paths: new Set<string>(),
        controllers: new Set<string>(),
        files: new Set<string>(),
        isResource: route.isResource,
      };
      helperMap.set(key, entry);
    }

    if (route.action) {
      entry.actions.add(route.action);
    }
    route.params.forEach(param => entry?.params.add(param));
    entry.verbs.add(route.verb);
    entry.paths.add(route.path);
    if (route.controller) {
      entry.controllers.add(route.controller);
    }
    entry.files.add(path.basename(route.filePath));
    entry.isResource = entry.isResource || route.isResource;
  });

  if (helperMap.size === 0) {
    return null;
  }

  const completions: CompletionItem[] = [];
  helperMap.forEach(group => {
    const helperBase = group.helperBase;
    const helperNamePath = `${helperBase}_path`;
    const helperNameUrl = `${helperBase}_url`;
    const lowerPartial = partial.toLowerCase();

    const variants: Array<{ variant: 'path' | 'url'; helperName: string }> = [
      { variant: 'path', helperName: helperNamePath },
      { variant: 'url', helperName: helperNameUrl },
    ];

    variants.forEach(({ variant, helperName }) => {
      if (lowerPartial && !helperName.toLowerCase().startsWith(lowerPartial)) {
        return;
      }

      const snippet = buildSnippet(helperBase, variant, group, routerRegistry);
      const documentation = buildHelperDocumentation(helperBase, variant, group, routerRegistry);

      completions.push({
        label: helperName,
        kind: CompletionItemKind.Function,
        detail: `Routes.${helperName}`,
        documentation: {
          kind: MarkupKind.Markdown,
          value: documentation,
        },
        insertTextFormat: InsertTextFormat.Snippet,
        textEdit: TextEdit.replace(range, snippet),
        sortText: `!0${helperName}`,
      });
    });
  });

  return completions.length > 0 ? completions : null;
}
