import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { TemplatesRegistry } from '../templates-registry';

/**
 * Validate controller template render calls
 * Checks:
 * 1. Template exists in corresponding HTML module
 * 2. Template files exist but are never used (warnings)
 */

/**
 * Extract controller module name from file path or content
 */
function extractControllerModule(filePath: string, fileContent: string): string | null {
  // Try from file content first to get full namespace: defmodule RaffleyWeb.PageController
  const moduleMatch = fileContent.match(/defmodule\s+([\w.]+Controller)\s+do/);
  if (moduleMatch) {
    return moduleMatch[1];
  }

  // Fallback to file path: page_controller.ex → PageController (no namespace)
  const fileMatch = filePath.match(/([a-z_]+)_controller\.ex$/);
  if (fileMatch) {
    const baseName = fileMatch[1];
    const pascalCase = baseName
      .split('_')
      .map(part => part.charAt(0).toUpperCase() + part.slice(1))
      .join('');
    return `${pascalCase}Controller`;
  }

  return null;
}

/**
 * Derive HTML module name from controller module
 */
function deriveHtmlModule(controllerModule: string): string {
  return controllerModule.replace(/Controller$/, 'HTML');
}

/**
 * Convert PascalCase module name to snake_case file/directory name
 * PageHTML → page_html
 * AdminUserHTML → admin_user_html
 * RaffleyWeb.PageHTML → page_html (extracts last part only)
 */
function toSnakeCase(pascalCase: string): string {
  // Extract last part of namespaced module (RaffleyWeb.PageHTML → PageHTML)
  const lastPart = pascalCase.split('.').pop() || pascalCase;

  return lastPart
    .replace(/([a-z])([A-Z])/g, '$1_$2')  // lowercase followed by uppercase
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')  // consecutive caps followed by cap+lowercase
    .toLowerCase();
}

/**
 * Validate template render calls in controllers
 */
export function validateTemplates(
  document: TextDocument,
  templatesRegistry: TemplatesRegistry
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();
  const uri = document.uri;

  // Only validate controller files
  if (!uri.endsWith('_controller.ex')) {
    return diagnostics;
  }

  const filePath = uri.replace('file://', '');
  const controllerModule = extractControllerModule(filePath, text);

  if (!controllerModule) {
    return diagnostics;
  }

  const htmlModule = deriveHtmlModule(controllerModule);

  // Match render calls: render(conn, :template), render!(conn, :template), Phoenix.Controller.render
  const renderPattern = /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*:([a-z_][a-z0-9_]*)/g;

  let match: RegExpExecArray | null;
  while ((match = renderPattern.exec(text)) !== null) {
    const templateName = match[1];
    const startOffset = match.index + match[0].lastIndexOf(':');
    const endOffset = startOffset + templateName.length + 1;

    // Skip if inside comment
    const lineStart = text.lastIndexOf('\n', match.index) + 1;
    const linePrefix = text.substring(lineStart, match.index);
    if (linePrefix.trim().startsWith('#')) {
      continue;
    }

    // Check if template exists
    const template = templatesRegistry.getTemplateByModule(htmlModule, templateName, 'html');

    if (!template) {
      // Debug: log all available templates for this module
      const allTemplates = templatesRegistry.getAllTemplates();
      const modulesFound = new Set(allTemplates.map(t => t.moduleName));

      // Only show error if we're confident the module should exist
      // Skip validation if the HTML module file doesn't exist in the registry
      if (!modulesFound.has(htmlModule)) {
        // HTML module not found in registry - skip validation
        // This might be a Phoenix 1.6 app using view modules instead
        continue;
      }

      const snakeCaseName = toSnakeCase(htmlModule);
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: document.positionAt(startOffset),
          end: document.positionAt(endOffset),
        },
        message: `Template "${templateName}" not found in ${htmlModule}. Create ${templateName}.html.heex in ${snakeCaseName}/ directory or add def ${templateName}(assigns) in ${snakeCaseName}.ex`,
        source: 'phoenix-lsp',
        code: 'template-not-found',
      });
    }
  }

  return diagnostics;
}

/**
 * Find unused templates (optional - for future warning feature)
 */
export function findUnusedTemplates(
  templatesRegistry: TemplatesRegistry,
  allControllerFiles: Map<string, string>
): string[] {
  const unusedTemplates: string[] = [];
  const allTemplates = templatesRegistry.getAllTemplates();
  const usedTemplates = new Set<string>();

  // Scan all controller files to find which templates are used
  for (const [filePath, content] of allControllerFiles.entries()) {
    const renderPattern = /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*:([a-z_][a-z0-9_]*)/g;
    let match: RegExpExecArray | null;

    while ((match = renderPattern.exec(content)) !== null) {
      usedTemplates.add(match[1]);
    }
  }

  // Find templates that are defined but never used
  for (const template of allTemplates) {
    if (!usedTemplates.has(template.name)) {
      unusedTemplates.push(`${template.moduleName}.${template.name}`);
    }
  }

  return unusedTemplates;
}
