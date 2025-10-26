import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { RouterRegistry } from '../router-registry';

/**
 * Validate Phoenix routes in templates and Elixir files
 * Checks:
 * 1. Verified routes (~p"...") exist in router
 * 2. Route helpers (Routes.user_path) exist
 * 3. Required parameters are provided
 * 4. <.link> navigation components use valid routes
 */

/**
 * Validate verified routes (~p"...")
 */
export function validateVerifiedRoutes(
  document: TextDocument,
  routerRegistry: RouterRegistry
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Match verified routes: ~p"/users" or ~p"/users/#{id}"
  const verifiedRoutePattern = /~p"([^"]+)"/g;

  let match: RegExpExecArray | null;
  while ((match = verifiedRoutePattern.exec(text)) !== null) {
    const fullPath = match[1];
    const startOffset = match.index;
    const endOffset = startOffset + match[0].length;

    // Skip if inside comment
    const lineStart = text.lastIndexOf('\n', startOffset) + 1;
    const linePrefix = text.substring(lineStart, startOffset);
    if (linePrefix.trim().startsWith('#')) {
      continue;
    }

    // Skip static asset paths (served by Phoenix automatically)
    // Common paths: /images/, /css/, /js/, /fonts/, /favicon.ico, /robots.txt
    const staticAssetPaths = ['/images/', '/css/', '/js/', '/fonts/', '/assets/'];
    const staticAssetFiles = ['/favicon.ico', '/robots.txt', '/apple-touch-icon'];
    const isStaticAsset = staticAssetPaths.some(prefix => fullPath.startsWith(prefix)) ||
                          staticAssetFiles.some(file => fullPath === file || fullPath.startsWith(file));
    if (isStaticAsset) {
      continue;
    }

    // Extract static path (remove interpolation)
    // ~p"/users/#{id}" -> "/users/:id"
    let routePath = fullPath.replace(/#\{[^}]+\}/g, ':param');

    // Try to find exact match first
    let route = routerRegistry.findRouteByPath(routePath);

    // If not found, try without interpolations
    if (!route) {
      const staticPath = fullPath.split('#')[0].replace(/\/$/, '');
      route = routerRegistry.findRouteByPath(staticPath);
    }

    // If still not found, try to find partial match
    if (!route) {
      const allRoutes = routerRegistry.getRoutes();
      const basePath = fullPath.split('?')[0].split('#')[0];

      route = allRoutes.find(r => {
        const routeBase = r.path.split('?')[0];
        return routeBase === basePath || r.path.startsWith(basePath);
      });
    }

    if (!route) {
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: document.positionAt(startOffset),
          end: document.positionAt(endOffset),
        },
        message: `Route "${fullPath}" not found in router. Check your router.ex file.`,
        source: 'phoenix-lsp',
        code: 'route-not-found',
      });
    }
  }

  return diagnostics;
}

/**
 * Validate route helper calls (Routes.user_path, etc.)
 */
export function validateRouteHelpers(
  document: TextDocument,
  routerRegistry: RouterRegistry
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Match Routes.helper_path(...) or Routes.helper_url(...)
  const routeHelperPattern = /Routes\.([a-z_]+)_(path|url)\s*\([^)]*\)/g;

  let match: RegExpExecArray | null;
  while ((match = routeHelperPattern.exec(text)) !== null) {
    const helperBase = match[1];
    const variant = match[2];
    const startOffset = match.index;
    const endOffset = startOffset + match[0].length;

    // Skip if inside comment
    const lineStart = text.lastIndexOf('\n', startOffset) + 1;
    const linePrefix = text.substring(lineStart, startOffset);
    if (linePrefix.trim().startsWith('#')) {
      continue;
    }

    const routes = routerRegistry.findRoutesByHelper(helperBase);

    if (routes.length === 0) {
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: document.positionAt(startOffset),
          end: document.positionAt(endOffset),
        },
        message: `Route helper "Routes.${helperBase}_${variant}" not found. Check your router.ex file.`,
        source: 'phoenix-lsp',
        code: 'route-helper-not-found',
      });
    }
  }

  return diagnostics;
}

/**
 * Validate route parameters
 * Checks if required parameters are provided
 */
export function validateRouteParameters(
  document: TextDocument,
  routerRegistry: RouterRegistry
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Match Routes.helper_path(conn, :action, params...)
  const routeCallPattern = /Routes\.([a-z_]+)_(path|url)\s*\(([^)]+)\)/g;

  let match: RegExpExecArray | null;
  while ((match = routeCallPattern.exec(text)) !== null) {
    const helperBase = match[1];
    const args = match[3];
    const startOffset = match.index;
    const endOffset = startOffset + match[0].length;

    // Skip if inside comment
    const lineStart = text.lastIndexOf('\n', startOffset) + 1;
    const linePrefix = text.substring(lineStart, startOffset);
    if (linePrefix.trim().startsWith('#')) {
      continue;
    }

    const routes = routerRegistry.findRoutesByHelper(helperBase);
    if (routes.length === 0) {
      continue; // Already handled by validateRouteHelpers
    }

    const route = routes[0];

    // Parse arguments (rough parsing, good enough for validation)
    const argList = args.split(',').map(a => a.trim());

    // First arg is conn/socket, second is optional action
    // Remaining args should match required params
    const requiredParamsCount = route.params.length;
    const hasAction = route.isResource;

    // Expected args: conn, [action], ...params
    const minArgs = hasAction ? 2 + requiredParamsCount : 1 + requiredParamsCount;

    if (argList.length < minArgs) {
      const missingParams = route.params.slice(argList.length - (hasAction ? 2 : 1));

      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: {
          start: document.positionAt(startOffset),
          end: document.positionAt(endOffset),
        },
        message: `Missing required parameter${missingParams.length > 1 ? 's' : ''}: ${missingParams.join(', ')}. Route "${route.path}" requires: ${route.params.join(', ')}`,
        source: 'phoenix-lsp',
        code: 'route-missing-params',
      });
    }
  }

  return diagnostics;
}

/**
 * Validate <.link> navigation components
 */
export function validateLinkComponents(
  document: TextDocument,
  routerRegistry: RouterRegistry
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();

  // Match <.link href="..." or <.link navigate="..." or <.link patch="..."
  const linkPattern = /<\.link\s+[^>]*(href|navigate|patch)\s*=\s*["']([^"']+)["']/g;

  let match: RegExpExecArray | null;
  while ((match = linkPattern.exec(text)) !== null) {
    const attrType = match[1];
    const attrValue = match[2];
    const startOffset = match.index + match[0].indexOf(attrValue);
    const endOffset = startOffset + attrValue.length;

    // Skip if it's a variable or expression
    if (attrValue.startsWith('@') || attrValue.includes('{') || attrValue.includes('<')) {
      continue;
    }

    // Skip external URLs
    if (attrValue.startsWith('http://') || attrValue.startsWith('https://')) {
      continue;
    }

    // Extract path (remove query string and anchor)
    const path = attrValue.split('?')[0].split('#')[0];

    // Try to find route
    let route = routerRegistry.findRouteByPath(path);

    // Try to match with parameters replaced
    if (!route && path.includes('/')) {
      const allRoutes = routerRegistry.getRoutes();
      route = allRoutes.find(r => {
        const routePattern = r.path.replace(/:[a-z_]+/g, '[^/]+');
        const regex = new RegExp(`^${routePattern}$`);
        return regex.test(path);
      });
    }

    if (!route && path !== '/' && path !== '#') {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: {
          start: document.positionAt(startOffset),
          end: document.positionAt(endOffset),
        },
        message: `Route "${path}" not found in router. The ${attrType} may not work.`,
        source: 'phoenix-lsp',
        code: 'link-route-not-found',
      });
    }
  }

  return diagnostics;
}

/**
 * Main route diagnostics function
 */
export function validateRoutes(
  document: TextDocument,
  routerRegistry: RouterRegistry
): Diagnostic[] {
  const allDiagnostics: Diagnostic[] = [];

  // Run all route validations
  allDiagnostics.push(...validateVerifiedRoutes(document, routerRegistry));
  allDiagnostics.push(...validateRouteHelpers(document, routerRegistry));
  allDiagnostics.push(...validateRouteParameters(document, routerRegistry));
  allDiagnostics.push(...validateLinkComponents(document, routerRegistry));

  return allDiagnostics;
}
