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

  test "infers legacy template, colocated component, layout, and LiveView variants" do
    cases = [
      {
        "file:///tmp/app/lib/app_web/templates/page/index.html.heex",
        "index.html",
        "AppWeb.PageView",
        :controller
      },
      {
        "file:///tmp/app/lib/app_web/templates/layout/app.html.heex",
        "app.html",
        "AppWeb.LayoutView",
        :layout
      },
      {
        "file:///tmp/app/lib/app_web/components/core_components.html.heex",
        "core_components.html",
        "AppWeb.CoreComponents",
        :component
      },
      {
        "file:///tmp/app/lib/app_web/components/layouts.html.heex",
        "layouts.html",
        "AppWeb.Layouts",
        :layout
      },
      {
        "file:///tmp/app/lib/app_web/live/product_live.html.heex",
        "product_live.html",
        "AppWeb.ProductLive",
        :live_view
      },
      {
        "file:///tmp/app/lib/app_web/live/product_live/index.html.heex",
        "index.html",
        "AppWeb.ProductLive.Index",
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

  test "uses embed_templates owner modules for non-conventional template directories" do
    root = System.unique_integer([:positive])
    tmp_root = Path.join(System.tmp_dir!(), "phoenix-ls-template-#{root}")
    controllers_dir = Path.join([tmp_root, "lib", "app_web", "controllers"])
    templates_dir = Path.join(controllers_dir, "site_templates")
    module_path = Path.join(controllers_dir, "marketing_html.ex")
    template_path = Path.join(templates_dir, "landing.html.heex")

    File.mkdir_p!(templates_dir)

    File.write!(module_path, """
    defmodule AppWeb.MarketingHTML do
      use AppWeb, :html

      embed_templates "site_templates/*"
    end
    """)

    File.write!(template_path, "<section />")

    try do
      uri = "file://" <> template_path

      assert [fact] = Template.facts(uri, "<section />")

      assert Map.take(Map.from_struct(fact.data), [:format, :name, :module, :kind]) == %{
               format: :heex,
               name: "landing.html",
               module: "AppWeb.MarketingHTML",
               kind: :controller
             }
    after
      File.rm_rf!(tmp_root)
    end
  end
end
