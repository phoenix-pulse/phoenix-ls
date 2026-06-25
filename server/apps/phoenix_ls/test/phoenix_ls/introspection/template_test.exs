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

  test "extracts literal LiveView event usages from HEEx phx attributes" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <button phx-click="save" phx-value-id="1">Save</button>
    <form phx-submit="missing" phx-change={@changeset}></form>
    """

    assert [save, missing] = Template.event_usage_facts(uri, source)

    assert save.kind == :live_event_usage
    assert save.data.module == "AppWeb.ProductLive"
    assert save.data.event == "save"
    assert save.data.attribute == "phx-click"
    assert save.data.handler == "handle_event/3"
    assert save.data.arity == 3
    assert save.range.start.line == 0
    assert save.range.start.character == 19

    assert missing.kind == :live_event_usage
    assert missing.data.module == "AppWeb.ProductLive"
    assert missing.data.event == "missing"
    assert missing.data.attribute == "phx-submit"
    assert missing.range.start.line == 1
  end

  test "extracts literal LiveView hook usages from HEEx phx-hook attributes" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"
    source = ~s(<div id="phone" phx-hook="PhoneNumber"></div>)

    assert [usage] = Template.hook_usage_facts(uri, source, version: 8)

    assert usage.kind == :hook_usage
    assert usage.uri == uri
    assert usage.data.module == "AppWeb.ProductLive"
    assert usage.data.name == "PhoneNumber"
    assert usage.data.attribute == "phx-hook"
    assert usage.data.tag == "div"
    assert usage.range.start.line == 0
    assert usage.range.start.character == 26
    assert usage.range.end.character == 37
    assert usage.provenance.source == :heex_template
    assert usage.provenance.document_version == 8
  end

  test "extracts colocated asset facts from HEEx script and style tags" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
      export default {}
    </script>

    <script :type={Phoenix.LiveView.ColocatedJS}>
      console.log("local")
    </script>

    <style :type={Phoenix.LiveView.ColocatedCSS}>
      .root {}
    </style>
    """

    assert [hook, js, css] = Template.colocated_asset_facts(uri, source, version: 11)

    assert hook.kind == :colocated_hook
    assert hook.data.owner_module == "AppWeb.ProductLive"
    assert hook.data.type_module == "Phoenix.LiveView.ColocatedHook"
    assert hook.data.name == ".Sortable"
    assert hook.data.generated_name == "AppWeb.ProductLive.Sortable"
    assert hook.data.tag == "script"
    assert hook.data.options == %{"name" => ".Sortable"}
    assert hook.range.start.line == 0
    assert hook.range.start.character == 0
    assert hook.data.source_range == hook.range
    assert hook.provenance.source == :heex_template
    assert hook.provenance.document_version == 11

    assert js.kind == :colocated_js
    assert js.data.owner_module == "AppWeb.ProductLive"
    assert js.data.type_module == "Phoenix.LiveView.ColocatedJS"
    assert js.data.name == nil
    assert js.data.generated_name == "AppWeb.ProductLive.ColocatedJS"
    assert js.data.tag == "script"
    assert js.data.options == %{}

    assert css.kind == :colocated_css
    assert css.data.owner_module == "AppWeb.ProductLive"
    assert css.data.type_module == "Phoenix.LiveView.ColocatedCSS"
    assert css.data.name == nil
    assert css.data.generated_name == "AppWeb.ProductLive.ColocatedCSS"
    assert css.data.tag == "style"
    assert css.data.options == %{}
  end

  test "extracts project-specific colocated asset type modules" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <script :type={MyAppWeb.ColocatedHook} name=".Sortable">
      export default {}
    </script>

    <script :type={MyAppWeb.ColocatedJS}>
      console.log("local")
    </script>

    <style :type={MyAppWeb.ColocatedCSS}>
      .root {}
    </style>
    """

    assert [hook, js, css] = Template.colocated_asset_facts(uri, source)

    assert {hook.kind, hook.data.type_module, hook.data.generated_name} ==
             {:colocated_hook, "MyAppWeb.ColocatedHook", "AppWeb.ProductLive.Sortable"}

    assert {js.kind, js.data.type_module, js.data.generated_name} ==
             {:colocated_js, "MyAppWeb.ColocatedJS", "AppWeb.ProductLive.ColocatedJS"}

    assert {css.kind, css.data.type_module, css.data.generated_name} ==
             {:colocated_css, "MyAppWeb.ColocatedCSS", "AppWeb.ProductLive.ColocatedCSS"}
  end

  test "builds template indexing facts with template, event, upload, hook usage, and colocated asset facts" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <button phx-click="save" phx-hook="PhoneNumber">Save</button>
    <.live_file_input upload={@uploads.avatar} />
    <script :type={Phoenix.LiveView.ColocatedJS}>
      console.log("local")
    </script>
    """

    facts = Template.index_facts(uri, source, version: 9)

    assert [%{data: %{name: "product_live.html"}}] = Enum.filter(facts, &(&1.kind == :template))
    assert [%{data: %{event: "save"}}] = Enum.filter(facts, &(&1.kind == :live_event_usage))
    assert [%{data: %{upload: "avatar"}}] = Enum.filter(facts, &(&1.kind == :upload_usage))
    assert [%{data: %{name: "PhoneNumber"}}] = Enum.filter(facts, &(&1.kind == :hook_usage))

    assert [%{data: %{generated_name: "AppWeb.ProductLive.ColocatedJS"}}] =
             Enum.filter(facts, &(&1.kind == :colocated_js))

    assert Enum.all?(facts, &(&1.provenance.document_version == 9))
  end

  test "extracts upload usage facts from HEEx assign, component, helper, and drop target usage" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <%= @uploads.avatar %>
    <.live_file_input upload={@uploads.avatar} />
    <p><%= upload_errors(@uploads.avatar) %></p>
    <section phx-drop-target={@uploads.avatar.ref}></section>
    """

    assert facts = Template.upload_usage_facts(uri, source, version: 7)

    assert Enum.map(facts, & &1.kind) == [
             :upload_usage,
             :upload_usage,
             :upload_usage,
             :upload_usage
           ]

    assert [assign, live_file_input, upload_errors, drop_target] = facts

    assert assign.data.module == "AppWeb.ProductLive"
    assert assign.data.upload == "avatar"
    assert assign.data.role == :assign
    assert assign.data.attribute == nil
    assert assign.data.function == nil
    assert assign.data.tag == nil
    assert assign.range.start.line == 0
    assert assign.range.start.character == 4
    assert assign.provenance.source == :heex_template
    assert assign.provenance.document_version == 7

    assert live_file_input.data.module == "AppWeb.ProductLive"
    assert live_file_input.data.upload == "avatar"
    assert live_file_input.data.role == :live_file_input
    assert live_file_input.data.attribute == "upload"
    assert live_file_input.data.tag == ".live_file_input"
    assert live_file_input.range.start.line == 1
    assert live_file_input.range.start.character == 26

    assert upload_errors.data.module == "AppWeb.ProductLive"
    assert upload_errors.data.upload == "avatar"
    assert upload_errors.data.role == :upload_errors
    assert upload_errors.data.function == "upload_errors/1"
    assert upload_errors.range.start.line == 2
    assert upload_errors.range.start.character == 7

    assert drop_target.data.module == "AppWeb.ProductLive"
    assert drop_target.data.upload == "avatar"
    assert drop_target.data.role == :drop_target
    assert drop_target.data.attribute == "phx-drop-target"
    assert drop_target.range.start.line == 3
    assert drop_target.range.start.character == 26
  end

  test "extracts upload_errors/2 upload usage facts" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"
    source = "<%= upload_errors(@uploads.avatar, :too_large) %>"

    assert [upload_errors] = Template.upload_usage_facts(uri, source)

    assert upload_errors.data.module == "AppWeb.ProductLive"
    assert upload_errors.data.upload == "avatar"
    assert upload_errors.data.role == :upload_errors
    assert upload_errors.data.function == "upload_errors/2"
  end

  test "extracts nested static upload paths from HEEx expressions" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <%= for entry <- @uploads.avatar.entries do %>
      <span><%= entry.client_name %></span>
    <% end %>
    """

    assert [usage] = Template.upload_usage_facts(uri, source)

    assert usage.data.module == "AppWeb.ProductLive"
    assert usage.data.upload == "avatar"
    assert usage.data.role == :assign
    assert usage.range.start.line == 0
    assert usage.range.start.character == 17
    assert usage.range.end.character == 32
  end

  test "keeps recoverable facts when a HEEx expression is incomplete" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    source = """
    <button phx-click="save">Save</button>
    <%= @uploads.avatar
    """

    assert [%{data: %{event: "save"}}] = Template.event_usage_facts(uri, source)
    assert [%{data: %{upload: "avatar"}}] = Template.upload_usage_facts(uri, source)
  end

  test "returns no upload usage facts for parse errors and dynamic upload expressions" do
    uri = "file:///tmp/app/lib/app_web/live/product_live.html.heex"

    assert [] = Template.upload_usage_facts(uri, "<section")

    source = """
    <.live_file_input upload={@uploads[selected]} />
    <%= upload_errors(@uploads[selected]) %>
    <section phx-drop-target={@uploads.avatar.dynamic_ref}></section>
    """

    assert [] = Template.upload_usage_facts(uri, source)
  end
end
