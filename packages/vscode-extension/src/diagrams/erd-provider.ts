import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { LanguageClient } from 'vscode-languageclient/node';
import { generateMermaidDiagram } from './mermaid-generator';

export class ErdProvider {
  private static currentPanel: vscode.WebviewPanel | undefined;

  public static async show(context: vscode.ExtensionContext, client: LanguageClient) {
    const column = vscode.ViewColumn.One;

    // If panel already exists, reveal it
    if (ErdProvider.currentPanel) {
      ErdProvider.currentPanel.reveal(column);
      return;
    }

    // Create new panel
    const panel = vscode.window.createWebviewPanel(
      'phoenixPulseERD',
      'Phoenix Schema Diagram',
      column,
      {
        enableScripts: true,
        retainContextWhenHidden: true
      }
    );

    ErdProvider.currentPanel = panel;

    // Reset when panel is closed
    panel.onDidDispose(() => {
      ErdProvider.currentPanel = undefined;
    }, null, context.subscriptions);

    // Load schemas from LSP
    try {
      const schemas = await client.sendRequest('phoenix/listSchemas', {});

      // Generate mermaid diagram
      const mermaidCode = generateMermaidDiagram(schemas);

      // Load HTML template
      const htmlPath = path.join(context.extensionPath, 'resources', 'erd-panel.html');
      let html = fs.readFileSync(htmlPath, 'utf-8');

      // Replace placeholder with actual mermaid code
      html = html.replace('{{MERMAID_DIAGRAM}}', mermaidCode);

      panel.webview.html = html;
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to load schema diagram: ${error}`);
    }
  }
}
