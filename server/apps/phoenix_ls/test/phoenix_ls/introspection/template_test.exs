defmodule PhoenixLS.Introspection.TemplateTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Template

  @uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

  test "extracts HEEx template facts with document ranges" do
    source = "<section>\n  <.button label=\"Save 😀\" />\n</section>\n"

    assert [fact] = Template.facts(@uri, source, version: 12)

    assert fact.kind == :template
    assert fact.id == @uri
    assert fact.uri == @uri
    assert fact.range.start.line == 0
    assert fact.range.start.character == 0
    assert fact.range.end.line == 3
    assert fact.range.end.character == 0

    assert fact.data == %Template.Template{
             format: :heex
           }

    assert fact.provenance.source == :heex_template
    assert fact.provenance.document_version == 12
  end
end
