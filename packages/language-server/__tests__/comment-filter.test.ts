import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { filterDiagnosticsInsideComments } from '../src/utils/comments';

function createDiagnostic(document: TextDocument, start: number, end: number): Diagnostic {
  return {
    severity: DiagnosticSeverity.Warning,
    range: {
      start: document.positionAt(start),
      end: document.positionAt(end),
    },
    message: 'Test diagnostic',
    source: 'phoenix-lsp',
  };
}

describe('comment diagnostics filter', () => {
  it('suppresses diagnostics inside HEEx comments', () => {
    const content = `<%!--\n  <.live_component id="modal" />\n--%>`;
    const document = TextDocument.create('file:///tmp/example.html.heex', 'phoenix-heex', 1, content);

    const diag = createDiagnostic(document, content.indexOf('<.live_component'), content.indexOf('/>') + 2);
    const filtered = filterDiagnosticsInsideComments(document, [diag]);

    expect(filtered.length).toBe(0);
  });

  it('suppresses diagnostics inside Elixir line comments', () => {
    const content = `
# phx-click="submit"
IO.inspect(:ok)
`;
    const document = TextDocument.create('file:///tmp/example.ex', 'elixir', 1, content);
    const diag = createDiagnostic(document, content.indexOf('phx-click'), content.indexOf('submit') + 'submit'.length);
    const filtered = filterDiagnosticsInsideComments(document, [diag]);

    expect(filtered.length).toBe(0);
  });

  it('keeps diagnostics outside comments', () => {
    const content = `<div phx-click="submit">OK</div>`;
    const document = TextDocument.create('file:///tmp/example.html.heex', 'phoenix-heex', 1, content);
    const diag = createDiagnostic(document, content.indexOf('phx-click'), content.indexOf('submit') + 'submit'.length);
    const filtered = filterDiagnosticsInsideComments(document, [diag]);

    expect(filtered.length).toBe(1);
  });

  it('suppresses diagnostics inside @doc strings', () => {
    const content = `@doc """
Example:

    <.list>
      <:item title="Title">{@post.title}</:item>
    </.list>
"""
`;
    const document = TextDocument.create('file:///tmp/example.ex', 'elixir', 1, content);
    const start = content.indexOf('<.list>');
    const end = content.indexOf('</.list>') + '</.list>'.length;
    const diag = createDiagnostic(document, start, end);
    const filtered = filterDiagnosticsInsideComments(document, [diag]);

    expect(filtered.length).toBe(0);
  });
});
