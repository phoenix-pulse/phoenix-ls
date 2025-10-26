import * as path from 'path';
import { CompletionItem, CompletionItemKind, MarkupKind } from 'vscode-languageserver/node';
import { TemplatesRegistry } from '../templates-registry';

/**
 * Controller template completions
 * Provides autocomplete for render(conn, :template) calls in controllers
 */

/**
 * Detect if cursor is in a render call context
 * Matches: render(conn, :, render!(conn, :, Phoenix.Controller.render(
 */
export function isRenderContext(linePrefix: string): boolean {
  // Match render(conn, : or render!(conn, : or Phoenix.Controller.render(conn, :
  return /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*:$/.test(linePrefix);
}

/**
 * Extract controller module name from file path or content
 */
function extractControllerModule(filePath: string, fileContent?: string): string | null {
  // Try from file content first to get full namespace: defmodule RaffleyWeb.PageController
  if (fileContent) {
    const moduleMatch = fileContent.match(/defmodule\s+([\w.]+Controller)\s+do/);
    if (moduleMatch) {
      return moduleMatch[1];
    }
  }

  // Fallback to file path: page_controller.ex → PageController (no namespace)
  const fileMatch = filePath.match(/([a-z_]+)_controller\.ex$/);
  if (fileMatch) {
    const baseName = fileMatch[1];
    // Convert snake_case to PascalCase
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
 * PageController → PageHTML
 * UserController → UserHTML
 */
function deriveHtmlModule(controllerModule: string): string {
  return controllerModule.replace(/Controller$/, 'HTML');
}

/**
 * Get template completions for controller render calls
 */
export function getTemplateCompletions(
  filePath: string,
  linePrefix: string,
  templatesRegistry: TemplatesRegistry,
  fileContent?: string
): CompletionItem[] | null {
  // Check if we're in a render context
  if (!isRenderContext(linePrefix)) {
    return null;
  }

  // Extract controller module from file
  const controllerModule = extractControllerModule(filePath, fileContent);
  if (!controllerModule) {
    return null;
  }

  // Derive HTML module (e.g., PageController → PageHTML)
  const htmlModule = deriveHtmlModule(controllerModule);

  // Get all templates for this HTML module
  const templates = templatesRegistry.getTemplatesForModule(htmlModule);

  if (templates.length === 0) {
    return null;
  }

  // Build completions
  const completions: CompletionItem[] = templates
    .filter(template => template.format === 'html') // Only HTML templates
    .map((template, index) => {
      const isEmbedded = template.filePath.endsWith('.ex');
      const templateType = isEmbedded ? 'Embedded template function' : 'Template file';
      const fileName = path.basename(template.filePath);

      return {
        label: `:${template.name}`,
        kind: CompletionItemKind.Value,
        detail: `${templateType}: ${fileName}`,
        documentation: {
          kind: MarkupKind.Markdown,
          value: `**Template:** \`${template.name}\`\n\n` +
                 `**Type:** ${templateType}\n\n` +
                 `**Location:** ${template.filePath}\n\n` +
                 `**Module:** ${template.moduleName}`,
        },
        insertText: template.name,
        filterText: `:${template.name}`,
        sortText: `!0${index.toString().padStart(3, '0')}`, // Sort by index
      };
    });

  return completions.length > 0 ? completions : null;
}

/**
 * Extract template name from render call
 * render(conn, :home) → 'home'
 * render!(conn, :about) → 'about'
 */
export function extractTemplateNameFromRenderCall(text: string, offset: number): {
  templateName: string;
  startOffset: number;
  endOffset: number;
} | null {
  // Find the render call containing the cursor
  const beforeCursor = text.substring(Math.max(0, offset - 200), offset);
  const afterCursor = text.substring(offset, Math.min(text.length, offset + 50));

  // Match: render(conn, :template_name
  const pattern = /(?:render!?|Phoenix\.Controller\.render)\s*\(\s*\w+\s*,\s*:([a-z_][a-z0-9_]*)/;
  const match = beforeCursor.match(pattern);

  if (match) {
    const templateName = match[1];
    const matchStart = offset - beforeCursor.length + match.index!;
    const colonPos = matchStart + match[0].lastIndexOf(':');

    return {
      templateName,
      startOffset: colonPos,
      endOffset: colonPos + templateName.length + 1,
    };
  }

  return null;
}
