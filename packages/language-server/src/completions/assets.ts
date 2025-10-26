import * as path from 'path';
import { CompletionItem, CompletionItemKind, TextEdit } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { AssetRegistry, AssetInfo } from '../asset-registry';

/**
 * Provide asset completions for ~p"/images/..." paths
 * Shows actual files from /priv/static/
 */
export function getAssetCompletions(
  document: TextDocument,
  position: { line: number; character: number },
  linePrefix: string,
  assetRegistry: AssetRegistry
): CompletionItem[] | null {
  // Try matching incomplete string first (when typing new path)
  const incompleteMatch = /~p\"([^\"]*)$/.exec(linePrefix);

  // Try matching inside existing string (when editing)
  const line = document.getText({
    start: { line: position.line, character: 0 },
    end: { line: position.line, character: 999 }
  });

  let partial: string | null = null;
  let startCharacter = 0;
  let endCharacter = position.character;

  if (incompleteMatch) {
    // Typing new path: ~p"/images/log█ (no closing quote)
    partial = incompleteMatch[1];
    startCharacter = position.character - partial.length;
  } else {
    // Editing existing path: ~p"/images/log█o.svg" (has closing quote)
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

  // Only provide asset completions for static asset paths
  const staticAssetPrefixes = ['/images/', '/css/', '/js/', '/fonts/', '/assets/'];
  const isAssetPath = staticAssetPrefixes.some(prefix => partial!.startsWith(prefix));

  if (!isAssetPath) {
    return null;
  }

  const assets = assetRegistry.findAssetsByPath(partial);
  console.log(`[getAssetCompletions] Partial: "${partial}", found ${assets.length} assets`);

  if (assets.length === 0) {
    return null;
  }

  const range = {
    start: { line: position.line, character: startCharacter },
    end: { line: position.line, character: endCharacter },
  };

  const completions = assets
    .slice(0, 100) // Limit to 100 results for performance
    .map((asset, index) => ({
      label: asset.publicPath, // Use full path so VS Code doesn't filter it
      kind: getCompletionKind(asset.type),
      detail: `${getAssetTypeLabel(asset.type)} • ${(asset.size / 1024).toFixed(1)} KB`,
      documentation: formatAssetDocumentation(asset),
      textEdit: TextEdit.replace(range, asset.publicPath),
      sortText: `!0${index.toString().padStart(3, '0')}`,
    }));

  console.log(`[getAssetCompletions] Returning ${completions.length} completions`);
  console.log(`[getAssetCompletions] First 3: ${completions.slice(0, 3).map(c => c.label).join(', ')}`);
  console.log(`[getAssetCompletions] Range: start=${range.start.character}, end=${range.end.character}`);

  return completions;
}

function getCompletionKind(type: AssetInfo['type']): CompletionItemKind {
  switch (type) {
    case 'image':
      return CompletionItemKind.File;
    case 'css':
      return CompletionItemKind.Color;
    case 'js':
      return CompletionItemKind.Module;
    case 'font':
      return CompletionItemKind.Property;
    default:
      return CompletionItemKind.File;
  }
}

function getAssetTypeLabel(type: AssetInfo['type']): string {
  switch (type) {
    case 'image':
      return 'Image';
    case 'css':
      return 'CSS';
    case 'js':
      return 'JavaScript';
    case 'font':
      return 'Font';
    default:
      return 'File';
  }
}

function formatAssetDocumentation(asset: AssetInfo): string {
  const sizeKB = (asset.size / 1024).toFixed(1);
  const type = asset.type.charAt(0).toUpperCase() + asset.type.slice(1);

  return `${type} • ${sizeKB} KB\n\nPath: ${asset.publicPath}`;
}
