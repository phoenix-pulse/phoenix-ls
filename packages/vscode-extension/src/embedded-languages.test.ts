import { describe, expect, it } from 'vitest';

import { embeddedDocumentAt } from './embedded-languages';

describe('embedded language virtual documents', () => {
  it('forwards HEEx files as HTML virtual documents with source-stable positions', () => {
    const source = '<div class="card">{@title}</div>';

    const embedded = embeddedDocumentAt({
      uri: 'file:///tmp/page.html.heex',
      languageId: 'phoenix-heex',
      text: source,
      position: { line: 0, character: 6 }
    });

    expect(embedded).toMatchObject({
      languageId: 'html',
      sourceUri: 'file:///tmp/page.html.heex'
    });
    expect(embedded?.virtualText).toBe(source);
    expect(embedded?.sourceToVirtual({ line: 0, character: 6 })).toEqual({
      line: 0,
      character: 6
    });
    expect(embedded?.virtualToSource({ line: 0, character: 6 })).toEqual({
      line: 0,
      character: 6
    });
  });

  it('forwards cursor positions inside Elixir ~H heredocs as HTML virtual documents', () => {
    const source = [
      'def render(assigns) do',
      '  ~H"""',
      '  <section class="panel">',
      '    {@title}',
      '  </section>',
      '  """',
      'end'
    ].join('\n');

    const embedded = embeddedDocumentAt({
      uri: 'file:///tmp/page_live.ex',
      languageId: 'elixir',
      text: source,
      position: { line: 2, character: 11 }
    });

    expect(embedded?.languageId).toBe('html');
    expect(embedded?.virtualText.split('\n')[0]).toMatch(/^ +$/);
    expect(embedded?.virtualText.split('\n')[1]).toBe('       ');
    expect(embedded?.virtualText.split('\n')[2]).toContain('<section class="panel">');
    expect(embedded?.sourceToVirtual({ line: 2, character: 11 })).toEqual({
      line: 2,
      character: 11
    });
  });

  it('forwards positions inside HEEx style tags as CSS virtual documents', () => {
    const source = [
      '<div>',
      '  <style>',
      '    .card { color: red; }',
      '  </style>',
      '</div>'
    ].join('\n');

    const embedded = embeddedDocumentAt({
      uri: 'file:///tmp/page.html.heex',
      languageId: 'phoenix-heex',
      text: source,
      position: { line: 2, character: 12 }
    });

    expect(embedded?.languageId).toBe('css');
    expect(embedded?.virtualText.split('\n')[2]).toContain('.card { color: red; }');
    expect(embedded?.sourceToVirtual({ line: 2, character: 12 })).toEqual({
      line: 2,
      character: 12
    });
  });

  it('forwards positions inside HEEx script tags as JavaScript virtual documents', () => {
    const source = [
      '<div>',
      '  <script>',
      '    const target = document.querySelector("#modal");',
      '  </script>',
      '</div>'
    ].join('\n');

    const embedded = embeddedDocumentAt({
      uri: 'file:///tmp/page.html.heex',
      languageId: 'phoenix-heex',
      text: source,
      position: { line: 2, character: 24 }
    });

    expect(embedded?.languageId).toBe('javascript');
    expect(embedded?.virtualText.split('\n')[2]).toContain('document.querySelector');
    expect(embedded?.sourceToVirtual({ line: 2, character: 24 })).toEqual({
      line: 2,
      character: 24
    });
  });

  it('does not forward Elixir positions outside HEEx sigils', () => {
    const embedded = embeddedDocumentAt({
      uri: 'file:///tmp/page_live.ex',
      languageId: 'elixir',
      text: 'def render(assigns), do: assigns',
      position: { line: 0, character: 4 }
    });

    expect(embedded).toBeNull();
  });
});
