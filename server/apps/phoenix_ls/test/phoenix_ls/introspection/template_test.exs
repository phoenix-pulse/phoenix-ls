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

    assert Map.take(Map.from_struct(fact.data), [:format, :name, :module, :kind]) == %{
             format: :heex,
             name: "index.html",
             module: "AppWeb.PageHTML",
             kind: :controller
           }

    assert fact.provenance.source == :heex_template
    assert fact.provenance.document_version == 12
  end

  test "infers template modules for Phoenix controller, layout, component, and LiveView paths" do
    cases = [
      {
        "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex",
        "index.html",
        "AppWeb.PageHTML",
        :controller
      },
      {
        "file:///tmp/app/lib/app_web/components/layouts/root.html.heex",
        "root.html",
        "AppWeb.Layouts",
        :layout
      },
      {
        "file:///tmp/app/lib/app_web/components/core_components/card.html.heex",
        "card.html",
        "AppWeb.CoreComponents",
        :component
      },
      {
        "file:///tmp/app/lib/app_web/live/product_live/show.html.heex",
        "show.html",
        "AppWeb.ProductLive.Show",
        :live_view
      }
    ]

    for {uri, name, module, kind} <- cases do
      assert [fact] = Template.facts(uri, "<section />")

      assert Map.take(Map.from_struct(fact.data), [:format, :name, :module, :kind]) == %{
               format: :heex,
               name: name,
               module: module,
               kind: kind
             }
    end
  end
end
