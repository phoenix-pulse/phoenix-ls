defmodule PhoenixLS.Features.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.Diagnostics
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Asset.Hooks, as: AssetHooks
  alias PhoenixLS.Introspection.Template
  alias PhoenixLS.Support.Fixtures

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"
  @live_template_uri "file:///tmp/app/lib/app_web/live/product_live.html.heex"

  test "reports missing required component attrs" do
    [diagnostic] = diagnostics("<.button />")

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Missing required attr "label" for .button)

    assert diagnostic.data == %{
             "kind" => "missing_required_attr",
             "tag" => ".button",
             "attr" => "label"
           }
  end

  test "reports missing required attrs on remote component tags" do
    [diagnostic] = diagnostics("<CoreComponents.button />")

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.message == ~s(Missing required attr "label" for CoreComponents.button)
  end

  test "reports unknown component attrs" do
    [diagnostic] = diagnostics(~s(<.button label="Save" unknown="x" />))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for .button)
  end

  test "reports local components that are unavailable in the template module" do
    source = "<.button />"
    {:ok, document} = Parser.parse(source)
    facts = facts() ++ Template.facts(@template_uri, source)

    [diagnostic] = Diagnostics.diagnostics(@template_uri, document, facts)

    assert diagnostic.code == "phoenix.component_not_imported"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Component .button is not imported in AppWeb.PageHTML)

    assert diagnostic.data == %{
             "kind" => "component_not_imported",
             "tag" => ".button",
             "component" => "button",
             "module" => "AppWeb.PageHTML"
           }
  end

  test "uses imports to validate local components in template modules" do
    source = "<.button />"
    {:ok, document} = Parser.parse(source)

    {:ok, html_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        import AppWeb.CoreComponents
      end
      """)

    facts = facts() ++ Template.facts(@template_uri, source) ++ html_facts

    [diagnostic] = Diagnostics.diagnostics(@template_uri, document, facts)

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.message == ~s(Missing required attr "label" for .button)
  end

  test "uses Phoenix web macro imports to validate local components in template modules" do
    source = "<.button />"
    {:ok, document} = Parser.parse(source)

    facts =
      facts() ++
        Template.facts(@template_uri, source) ++
        page_html_uses_web_macro_facts() ++
        web_macro_import_facts()

    [diagnostic] = Diagnostics.diagnostics(@template_uri, document, facts)

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.message == ~s(Missing required attr "label" for .button)
  end

  test "reports unknown attrs on remote component tags" do
    [diagnostic] = diagnostics(~s(<CoreComponents.button label="Save" unknown="x" />))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for CoreComponents.button)
  end

  test "does not report unknown slots without a resolved parent component" do
    assert diagnostics("<:footer />") == []
  end

  test "accepts generated Phoenix component slots and default inner blocks" do
    assert diagnostics(
             """
             <.header>
               Product {@product.id}
               <:subtitle>This is a product record from your database.</:subtitle>
               <:actions>
                 <span>Edit product</span>
               </:actions>
             </.header>

             <.list>
               <:item title="Title">{@product.title}</:item>
               <:item title="Slug">{@product.slug}</:item>
             </.list>
             """,
             Fixtures.generated_core_component_facts()
           ) == []
  end

  test "accepts generated Phoenix component directives and forwarded global attrs" do
    assert diagnostics(
             """
             <.modal :if={@live_action == :edit} id="product-modal">
               Modal content
             </.modal>

             <.simple_form :let={f} for={@form} action="/orders">
               <.input field={f[:price]} type="number" step="0.01" />
             </.simple_form>

             <.metric_card :for={metric <- @metrics} title={metric.title} />
             """,
             Fixtures.generated_core_component_facts()
           ) == []
  end

  test "reports unknown slot attrs" do
    [diagnostic] = diagnostics(~s(<.button label="Save"><:inner_block unknown="x" /></.button>))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for :inner_block)
  end

  test "reports slots not declared by the active component" do
    [diagnostic] = diagnostics("<.button><:footer /></.button>", slot_scope_facts())

    assert diagnostic.code == "phoenix.unknown_slot"
    assert diagnostic.message == ~s(Unknown slot ":footer")
  end

  test "reports slot attrs not declared by the active component slot" do
    [diagnostic] =
      diagnostics(~s(<.button><:item role="navigation" /></.button>), slot_scope_facts())

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "role" for :item)

    assert diagnostics(~s(<.card><:item role="navigation" /></.card>), slot_scope_facts()) == []
  end

  test "reports missing required slot attrs" do
    [diagnostic] = diagnostics("<.list><:item /></.list>", required_slot_attr_facts())

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Missing required attr "label" for :item)

    assert diagnostic.data == %{
             "kind" => "missing_required_attr",
             "tag" => ":item",
             "attr" => "label"
           }
  end

  test "reports missing required component slots" do
    [diagnostic] = diagnostics("<.list />", required_slot_facts())

    assert diagnostic.code == "phoenix.missing_required_slot"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Missing required slot ":item" for .list)

    assert diagnostic.data == %{
             "kind" => "missing_required_slot",
             "tag" => ".list",
             "slot" => "item"
           }
  end

  test "reports invalid attr values" do
    [diagnostic] = diagnostics(~s(<.button label="Save" kind="danger" />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for .button kind)

    assert diagnostic.data == %{
             "kind" => "invalid_attr_value",
             "tag" => ".button",
             "attr" => "kind",
             "value" => "danger",
             "values" => ["primary", "secondary"]
           }
  end

  test "reports invalid attr values on remote component tags" do
    [diagnostic] = diagnostics(~s(<CoreComponents.button label="Save" kind="danger" />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for CoreComponents.button kind)
  end

  test "reports invalid atom expression attr values" do
    [diagnostic] = diagnostics(~s(<.button label="Save" kind={:danger} />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for .button kind)

    assert diagnostic.data == %{
             "kind" => "invalid_attr_value",
             "tag" => ".button",
             "attr" => "kind",
             "value" => "danger",
             "values" => ["primary", "secondary"],
             "replacementValues" => [":primary", ":secondary"]
           }
  end

  test "does not report valid atom expression attr values" do
    assert diagnostics(~s(<.button label="Save" kind={:primary} />)) == []
  end

  test "reports invalid boolean expression attr values with boolean replacements" do
    [diagnostic] = diagnostics(~s(<.toggle enabled={:maybe} />))

    assert diagnostic.code == "phoenix.invalid_attr_value"

    assert diagnostic.data == %{
             "kind" => "invalid_attr_value",
             "tag" => ".toggle",
             "attr" => "enabled",
             "value" => "maybe",
             "values" => ["true", "false"],
             "replacementValues" => ["true", "false"]
           }
  end

  test "reports missing LiveComponent id and module attrs" do
    diagnostics = diagnostics("<.live_component />")

    assert Enum.map(diagnostics, & &1.code) == [
             "phoenix.missing_live_component_attr",
             "phoenix.missing_live_component_attr"
           ]

    assert Enum.map(diagnostics, & &1.message) == [
             ~s(Missing required attr "id" for .live_component),
             ~s(Missing required attr "module" for .live_component)
           ]

    assert Enum.map(diagnostics, & &1.data) == [
             %{
               "kind" => "missing_live_component_attr",
               "tag" => ".live_component",
               "attr" => "id"
             },
             %{
               "kind" => "missing_live_component_attr",
               "tag" => ".live_component",
               "attr" => "module"
             }
           ]
  end

  test "reports bad phx event names" do
    [diagnostic] = diagnostics(~s(<button phx-click="missing">))

    assert diagnostic.code == "phoenix.unknown_event"
    assert diagnostic.message == ~s(Missing handle_event/3 handler for LiveView event "missing")

    assert diagnostic.data == %{
             "kind" => "missing_live_event_handler",
             "event" => "missing",
             "attribute" => "phx-click",
             "handler" => "handle_event/3",
             "knownEvents" => ["save"]
           }
  end

  test "reports phx event names missing from the template LiveView module" do
    source = ~s(<button phx-click="save-admin">)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(@live_template_uri, document, live_event_scope_facts(source))

    assert diagnostic.code == "phoenix.unknown_event"

    assert diagnostic.message ==
             ~s(Missing handle_event/3 handler for LiveView event "save-admin")

    assert diagnostic.data == %{
             "kind" => "missing_live_event_handler",
             "event" => "save-admin",
             "attribute" => "phx-click",
             "handler" => "handle_event/3",
             "knownEvents" => ["save-product"]
           }
  end

  test "accepts phx event names from the template LiveView module" do
    source = ~s(<button phx-click="save-product">)
    {:ok, document} = Parser.parse(source)

    assert Diagnostics.diagnostics(@live_template_uri, document, live_event_scope_facts(source)) ==
             []
  end

  test "does not report expression-based phx event values as unknown events" do
    assert diagnostics(~S|<button phx-click={JS.show(to: "#modal")} />|) == []
  end

  test "reports exact invalid LiveView JS command option names" do
    [diagnostic] = diagnostics(~S|<button phx-click={JS.show(unknown: "#modal")} />|)

    assert diagnostic.code == "phoenix.invalid_live_view_js_option"
    assert diagnostic.message == ~s(Unknown JS.show option :unknown)

    assert diagnostic.data == %{
             "kind" => "invalid_live_view_js_option",
             "command" => "show",
             "option" => "unknown",
             "knownOptions" => ["to", "transition", "time", "display", "blocking"]
           }
  end

  test "does not validate dynamic LiveView JS command expressions" do
    assert diagnostics(~S|<button phx-click={JS.show(options)} />|) == []
    assert diagnostics(~S|<button phx-click={build_js(@target)} />|) == []
  end

  test "reports unknown phx attribute names" do
    [diagnostic] = diagnostics(~s(<button phx-clik="save">))

    assert diagnostic.code == "phoenix.unknown_phx_attr"
    assert diagnostic.message == ~s(Unknown Phoenix attr "phx-clik")
  end

  test "does not report known non-event phx attrs as unknown events" do
    assert diagnostics(
             ~s(<div phx-hook="Map" phx-debounce="300" phx-throttle="1000" phx-feedback-for="user[email]" />)
           ) == []
  end

  test "reports invalid constrained phx attr values" do
    [diagnostic] = diagnostics(~s(<div phx-update="morph" />))

    assert diagnostic.code == "phoenix.invalid_phx_attr_value"
    assert diagnostic.message == ~s(Invalid value "morph" for phx-update)

    assert diagnostic.data == %{
             "kind" => "invalid_phx_attr_value",
             "attr" => "phx-update",
             "value" => "morph",
             "values" => ["replace", "stream", "ignore"]
           }
  end

  test "does not report valid constrained phx attr values" do
    assert diagnostics(~s(<div phx-update="replace" />)) == []
    assert diagnostics(~s(<div phx-update="ignore" />)) == []
    assert diagnostics(~s(<div phx-update="stream" />)) == []
  end

  test "accepts dynamic HEEx attr maps without unknown attr diagnostics" do
    assert diagnostics(~s(<div {@attrs}></div>)) == []

    assert diagnostics(
             ~s(<.input {@rest} />),
             Fixtures.generated_core_component_facts()
           ) == []
  end

  test "reports mismatched HEEx closing tags" do
    [diagnostic] = diagnostics(~s(<div><span></div>))

    assert diagnostic.code == "phoenix.mismatched_closing_tag"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Expected closing tag </span>, found </div>.)

    assert diagnostic.data == %{
             "kind" => "mismatched_closing_tag",
             "expected" => "span",
             "actual" => "div"
           }
  end

  test "reports duplicate literal HEEx attrs" do
    [diagnostic] = diagnostics(~s(<div id="first" id="second"></div>))

    assert diagnostic.code == "phoenix.duplicate_attr"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Duplicate attr "id" on div.)

    assert diagnostic.data == %{
             "kind" => "duplicate_attr",
             "tag" => "div",
             "attr" => "id"
           }
  end

  test "reports void HEEx elements with child tags" do
    [diagnostic] = diagnostics(~s(<input><span></span></input>))

    assert diagnostic.code == "phoenix.void_element_child"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Void element "input" must not have child content.)

    assert diagnostic.data == %{
             "kind" => "void_element_child",
             "tag" => "input"
           }
  end

  test "reports HTML :for loops without DOM tracking" do
    [diagnostic] = diagnostics(~s(<div :for={item <- @items}>{item.name}</div>))

    assert diagnostic.code == "phoenix.for_missing_key"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ~s(HTML element "div" with :for should have DOM tracking)

    assert diagnostic.data == %{
             "kind" => "for_missing_key",
             "tag" => "div",
             "item" => "item"
           }
  end

  test "does not require :key for tracked or component :for loops" do
    assert diagnostics(~s(<div :for={item <- @items} :key={item.id}>{item.name}</div>)) == []
    assert diagnostics(~s(<div :for={item <- @items} id={item.id}>{item.name}</div>)) == []

    assert diagnostics("""
           <div phx-update="stream">
             <div :for={{dom_id, item} <- @streams.items} id={dom_id}>{item.name}</div>
           </div>
           """) == []

    assert diagnostics(~s(<.card :for={item <- @items} />)) == []
  end

  test "reports stream loops without tuple destructuring" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={user <- @streams.users} id={user.id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_invalid_pattern"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message =~ "{dom_id, user} <- @streams.users"
  end

  test "reports stream loops without dom id tracking" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={{dom_id, user} <- @streams.users}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_missing_id"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message =~ "id={dom_id}"
  end

  test "reports stream loops without phx-update stream container" do
    [diagnostic] =
      diagnostics("""
      <table>
        <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_missing_phx_update"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ~s(phx-update="stream")
  end

  test "reports unnecessary stream :key usage" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={{dom_id, user} <- @streams.users} :key={user.id} id={dom_id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_unnecessary_key"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ":key"
    assert diagnostic.message =~ "id={dom_id}"
  end

  test "reports unknown LiveView upload names in live_file_input" do
    source = ~s(<.live_file_input upload={@uploads.missing} />)
    [diagnostic] = diagnostics(source, upload_facts(source))

    assert diagnostic.code == "phoenix.unknown_upload"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Unknown LiveView upload "missing")

    assert diagnostic.data == %{
             "kind" => "unknown_upload",
             "module" => "AppWeb.ProductLive",
             "upload" => "missing",
             "knownUploads" => ["avatar"]
           }
  end

  test "reports upload forms missing phx-change" do
    source = """
    <form phx-submit="save">
      <.live_file_input upload={@uploads.avatar} />
    </form>
    """

    [diagnostic] = diagnostics(source, upload_facts(source))

    assert diagnostic.code == "phoenix.upload_form_missing_phx_change"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Upload form containing @uploads.avatar should define phx-change.)

    assert diagnostic.data == %{
             "kind" => "upload_form_missing_binding",
             "binding" => "phx-change",
             "module" => "AppWeb.ProductLive",
             "upload" => "avatar",
             "tag" => "form"
           }
  end

  test "reports upload forms missing phx-submit" do
    source = """
    <form phx-change="validate">
      <.live_file_input upload={@uploads.avatar} />
    </form>
    """

    [diagnostic] = diagnostics(source, upload_facts(source))

    assert diagnostic.code == "phoenix.upload_form_missing_phx_submit"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Upload form containing @uploads.avatar should define phx-submit.)

    assert diagnostic.data == %{
             "kind" => "upload_form_missing_binding",
             "binding" => "phx-submit",
             "module" => "AppWeb.ProductLive",
             "upload" => "avatar",
             "tag" => "form"
           }
  end

  test "reports upload Phoenix forms missing phx-change" do
    source = """
    <.form phx-submit="save">
      <.live_file_input upload={@uploads.avatar} />
    </.form>
    """

    [diagnostic] = diagnostics(source, upload_facts(source))

    assert diagnostic.code == "phoenix.upload_form_missing_phx_change"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Upload form containing @uploads.avatar should define phx-change.)

    assert diagnostic.data == %{
             "kind" => "upload_form_missing_binding",
             "binding" => "phx-change",
             "module" => "AppWeb.ProductLive",
             "upload" => "avatar",
             "tag" => ".form"
           }
  end

  test "scopes upload diagnostics to the current template uri" do
    source = """
    <form phx-change="validate" phx-submit="save">
      <.live_file_input upload={@uploads.avatar} />
    </form>
    """

    {:ok, document} = Parser.parse(source)

    other_uri = "file:///tmp/app/lib/app_web/live/other_live.html.heex"

    other_usage_facts =
      Template.upload_usage_facts(other_uri, ~s(<.live_file_input upload={@uploads.missing} />))

    assert Diagnostics.diagnostics(
             @live_template_uri,
             document,
             upload_facts(source) ++ other_usage_facts
           ) == []
  end

  test "reports unknown literal LiveView hook names" do
    source = ~s(<div phx-hook="MissingHook"></div>)
    {:ok, document} = Parser.parse(source)

    [diagnostic] = Diagnostics.diagnostics(@live_template_uri, document, hook_facts(source))

    assert diagnostic.code == "phoenix.unknown_hook"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Unknown LiveView hook "MissingHook")

    assert diagnostic.data == %{
             "kind" => "unknown_hook",
             "name" => "MissingHook",
             "attribute" => "phx-hook",
             "knownHooks" => ["PhoneNumber"]
           }
  end

  test "accepts known literal LiveView hook names" do
    source = ~s(<div phx-hook="PhoneNumber"></div>)
    {:ok, document} = Parser.parse(source)

    assert Diagnostics.diagnostics(@live_template_uri, document, hook_facts(source)) == []
  end

  test "reports invalid colocated hook names" do
    {source, expected_range} =
      source_and_range(
        ~s(<script :type={Phoenix.LiveView.ColocatedHook} name="[!Sortable!]"></script>)
      )

    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(
        @live_template_uri,
        document,
        Template.colocated_asset_facts(@live_template_uri, source)
      )

    assert diagnostic.code == "phoenix.invalid_colocated_hook_name"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Invalid colocated hook name "Sortable")
    assert diagnostic.range == expected_range

    assert diagnostic.data == %{
             "kind" => "invalid_colocated_hook_name",
             "name" => "Sortable",
             "expected" => "dot-prefixed PascalCase, for example .Sortable"
           }
  end

  test "accepts valid colocated hook names" do
    source = ~s(<script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable"></script>)
    {:ok, document} = Parser.parse(source)

    assert Diagnostics.diagnostics(
             @live_template_uri,
             document,
             Template.colocated_asset_facts(@live_template_uri, source)
           ) == []
  end

  test "does not leak hook usage facts into document-only diagnostics" do
    {:ok, document} = Parser.parse("<div></div>")

    other_uri = "file:///tmp/app/lib/app_web/live/other_live.html.heex"

    other_usage_facts =
      Template.hook_usage_facts(other_uri, ~s(<div phx-hook="MissingHook"></div>))

    diagnostics = Diagnostics.diagnostics(document, other_usage_facts)

    refute Enum.any?(diagnostics, &(&1.code == "phoenix.unknown_hook"))
  end

  test "reports unknown verified routes" do
    [diagnostic] = diagnostics(~s(<.link navigate={~p"/missing"} />))

    assert diagnostic.code == "phoenix.unknown_route"
    assert diagnostic.message == ~s(Unknown verified route "/missing")
  end

  test "accepts dynamic verified routes" do
    assert diagnostics(~s(<.link navigate={~p"/products/123"} />)) == []
  end

  test "accepts generated Phoenix static asset verified routes" do
    assert diagnostics("""
           <img src={~p"/images/logo.svg"} />
           <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
           <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
           """) == []
  end

  test "warns when patch navigation targets a different LiveView" do
    source = ~s(<.link patch={~p"/other-live"} />)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(@live_template_uri, document, live_navigation_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_patch"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message == ~s(Patch navigation to "/other-live" targets AppWeb.OtherLive.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_patch",
             "navigation" => "patch",
             "path" => "/other-live",
             "currentModule" => "AppWeb.ProductLive",
             "targetModule" => "AppWeb.OtherLive"
           }
  end

  test "warns when HEEx patch targets a known non-LiveView route" do
    source = ~s(<.link patch={~p"/login"} />)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(@live_template_uri, document, non_live_navigation_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_patch"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Patch navigation to "/login" targets non-LiveView route GET /login.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_patch",
             "navigation" => "patch",
             "path" => "/login",
             "currentModule" => "AppWeb.ProductLive",
             "targetKind" => "route",
             "targetVerb" => "get",
             "targetModule" => "AppWeb.SessionController"
           }
  end

  test "warns when navigate crosses live sessions" do
    source = ~s(<.link navigate={~p"/different-session"} />)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(@live_template_uri, document, live_navigation_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_navigate"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Navigate to "/different-session" changes live session from public to admin.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_navigate",
             "navigation" => "navigate",
             "path" => "/different-session",
             "currentModule" => "AppWeb.ProductLive",
             "targetModule" => "AppWeb.AdminLive",
             "currentLiveSession" => "public",
             "targetLiveSession" => "admin"
           }
  end

  test "does not run LiveView navigation checks for controller templates" do
    source = ~s(<.back navigate={~p"/orders"}>Back to orders</.back>)
    {:ok, document} = Parser.parse(source)

    facts =
      Fixtures.generated_core_component_facts() ++
        Template.facts(@template_uri, source) ++
        imported_page_html_facts() ++
        route_facts("""
        defmodule AppWeb.Router do
          use Phoenix.Router

          scope "/", AppWeb do
            get "/orders", OrderController, :index
          end
        end
        """)

    assert Diagnostics.diagnostics(@template_uri, document, facts) == []
  end

  test "warns when navigate crosses sessions for a LiveView mounted in multiple sessions" do
    source = ~s(<.link navigate={~p"/admin/settings"} />)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(
        @live_template_uri,
        document,
        multi_session_navigation_facts(source)
      )

    assert diagnostic.code == "phoenix.invalid_live_navigate"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Navigate to "/admin/settings" changes live session from public to admin.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_navigate",
             "navigation" => "navigate",
             "path" => "/admin/settings",
             "currentModule" => "AppWeb.ProductLive",
             "targetModule" => "AppWeb.SettingsLive",
             "currentLiveSession" => "public",
             "targetLiveSession" => "admin"
           }
  end

  test "uses HEEx action context when checking multi-session LiveView navigation" do
    source = ~s(<.link navigate={~p"/admin/settings"} />)
    {:ok, document} = Parser.parse(source)
    {template_uri, facts, cleanup} = admin_template_navigation_facts(source)

    try do
      assert Diagnostics.diagnostics(template_uri, document, facts) == []
    after
      cleanup.()
    end
  end

  test "warns when source push_patch targets a different LiveView" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("show-other", _params, socket) do
        {:noreply, push_patch(socket, to: ~p"/other-live")}
      end
    end
    """

    [diagnostic] = Diagnostics.diagnostics(@uri, live_navigation_source_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_patch"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message == ~s(Patch navigation to "/other-live" targets AppWeb.OtherLive.)
  end

  test "warns when source push_navigate targets a known non-LiveView route" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("login", _params, socket) do
        {:noreply, push_navigate(socket, to: ~p"/login")}
      end
    end
    """

    [diagnostic] = Diagnostics.diagnostics(@uri, non_live_source_navigation_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_navigate"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Navigate to "/login" targets non-LiveView route GET /login.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_navigate",
             "navigation" => "navigate",
             "path" => "/login",
             "currentModule" => "AppWeb.ProductLive",
             "targetKind" => "route",
             "targetVerb" => "get",
             "targetModule" => "AppWeb.SessionController"
           }
  end

  test "warns when dynamic source push_patch lacks handle_params" do
    source = ~S"""
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("show", %{"id" => id}, socket) do
        {:noreply, push_patch(socket, to: ~p"/products/#{id}")}
      end
    end
    """

    [diagnostic] = Diagnostics.diagnostics(@uri, dynamic_source_navigation_facts(source))

    assert diagnostic.code == "phoenix.missing_handle_params"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.data == %{
             "kind" => "missing_handle_params",
             "navigation" => "patch",
             "path" => "/products/:dynamic",
             "module" => "AppWeb.ProductLive",
             "callback" => "handle_params/3"
           }
  end

  test "uses router order for overlapping dynamic source navigation targets" do
    source = ~S"""
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_params(_params, _uri, socket), do: {:noreply, socket}

      def handle_event("show", %{"id" => id}, socket) do
        {:noreply, push_patch(socket, to: ~p"/products/#{id}")}
      end
    end
    """

    [diagnostic] =
      Diagnostics.diagnostics(@uri, overlapping_dynamic_source_navigation_facts(source))

    assert diagnostic.code == "phoenix.invalid_live_patch"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             ~s(Patch navigation to "/products/:dynamic" targets non-LiveView route GET /products/:id.)

    assert diagnostic.data == %{
             "kind" => "invalid_live_patch",
             "navigation" => "patch",
             "path" => "/products/:dynamic",
             "currentModule" => "AppWeb.ProductLive",
             "targetKind" => "route",
             "targetVerb" => "get",
             "targetModule" => "AppWeb.ProductController"
           }
  end

  test "warns when patch navigation targets current LiveView without handle_params" do
    source = ~s(<.link patch={~p"/products"} />)
    {:ok, document} = Parser.parse(source)

    [diagnostic] =
      Diagnostics.diagnostics(@live_template_uri, document, live_navigation_facts(source))

    assert diagnostic.code == "phoenix.missing_handle_params"
    assert diagnostic.severity == DiagnosticSeverity.warning()

    assert diagnostic.message ==
             "Patch navigation for AppWeb.ProductLive requires handle_params/3."

    assert diagnostic.data == %{
             "kind" => "missing_handle_params",
             "navigation" => "patch",
             "path" => "/products",
             "module" => "AppWeb.ProductLive",
             "callback" => "handle_params/3"
           }
  end

  test "reports unknown controller render templates" do
    [diagnostic] = Diagnostics.diagnostics(@controller_uri, controller_facts(:missing))

    assert diagnostic.code == "phoenix.unknown_template"
    assert diagnostic.message == ~s(Unknown template "missing.html.heex")
  end

  test "reports one unknown template diagnostic for controller render atoms" do
    {:ok, facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        use Phoenix.Controller

        def index(conn, _params) do
          render(conn, :missing)
        end
      end
      """)

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.unknown_template"
    assert diagnostic.message == ~s(Unknown template "missing.html.heex")
    assert diagnostic.range.start.character == 17
    assert diagnostic.range.end.character == 25
  end

  test "reports unknown pipeline controller render templates" do
    {:ok, facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        use Phoenix.Controller

        def index(conn, _params) do
          conn
          |> render(:missing)
        end
      end
      """)

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.unknown_template"
    assert diagnostic.message == ~s(Unknown template "missing.html.heex")
  end

  test "does not report html template diagnostics for json-only controller routes" do
    {:ok, router_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        pipeline :api do
          plug :accepts, ["json"]
        end

        scope "/api", AppWeb do
          pipe_through :api

          resources "/tickets", TicketController, except: [:new, :edit]
        end
      end
      """)

    {:ok, controller_facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.TicketController do
        use AppWeb, :controller

        def index(conn, _params) do
          render(conn, :index, tickets: [])
        end

        def show(conn, %{"id" => id}) do
          render(conn, :show, ticket: id)
        end
      end
      """)

    assert Diagnostics.diagnostics(@controller_uri, router_facts ++ controller_facts) == []
  end

  test "reports unknown route helpers" do
    facts =
      route_helper_facts("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.missing_path(conn, :index)
        end
      end
      """)

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.unknown_route_helper"
    assert diagnostic.message == ~s(Unknown route helper "missing_path")
  end

  test "reports unknown route helper actions" do
    facts =
      route_helper_facts("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_path(conn, :edit)
        end
      end
      """)

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.unknown_route_helper_action"
    assert diagnostic.message == ~s(Unknown action :edit for route helper "product_path")

    assert diagnostic.data == %{
             "kind" => "unknown_route_helper_action",
             "helper" => "product_path",
             "action" => "edit",
             "validActions" => ["index"]
           }
  end

  test "reports route helper arity mismatches" do
    facts =
      route_helper_facts(
        """
        defmodule AppWeb.PageController do
          def show(conn, _params) do
            Routes.product_path(conn, :show)
          end
        end
        """,
        """
        defmodule AppWeb.Router do
          use Phoenix.Router

          scope "/", AppWeb do
            live "/products/:id", ProductLive.Show, :show
          end
        end
        """
      )

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.route_helper_arity_mismatch"
    assert diagnostic.message == ~s(Route helper "product_path" expects 3 arguments but got 2)

    assert diagnostic.data == %{
             "kind" => "route_helper_arity_mismatch",
             "helper" => "product_path",
             "actualArity" => 2,
             "expectedArities" => [3]
           }
  end

  test "returns no diagnostics for known Phoenix usage" do
    assert diagnostics(~s(<.button label="Save" kind="primary" />)) == []

    assert diagnostics(~s(<.button label="Save"><:inner_block /></.button>)) == []

    assert diagnostics(~s(<.button label="Save"><:inner_block class="p-2" /></.button>)) == []

    assert diagnostics(~s(<button phx-click="save">)) == []
    assert diagnostics(~s(<.link navigate={~p"/products"} />)) == []
  end

  test "returns no diagnostics for known controller render templates" do
    facts = controller_facts(:index) ++ Template.facts(@template_uri, "<h1>Index</h1>")

    assert Diagnostics.diagnostics(@controller_uri, facts) == []
  end

  test "returns no diagnostics for known route helpers" do
    facts =
      route_helper_facts("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_path(conn, :index)
        end
      end
      """)

    assert Diagnostics.diagnostics(@controller_uri, facts) == []
  end

  defp diagnostics(source) do
    diagnostics(source, facts())
  end

  defp diagnostics(source, facts) do
    {:ok, document} = Parser.parse(source)

    result = Diagnostics.diagnostics(document, facts)

    assert Enum.all?(result, &match?(%Diagnostic{source: "PhoenixLS"}, &1))

    result
  end

  defp source_and_range(marked_source) do
    start_marker = "[!"
    end_marker = "!]"
    [{start_offset, _start_size}] = :binary.matches(marked_source, start_marker)
    [{end_marker_offset, _end_size}] = :binary.matches(marked_source, end_marker)

    source =
      marked_source
      |> String.replace(start_marker, "")
      |> String.replace(end_marker, "")

    end_offset = end_marker_offset - byte_size(start_marker)

    {:ok, start_position} =
      PhoenixLS.Support.Positions.offset_to_lsp_position(source, start_offset)

    {:ok, end_position} = PhoenixLS.Support.Positions.offset_to_lsp_position(source, end_offset)

    {
      source,
      %GenLSP.Structures.Range{
        start: %GenLSP.Structures.Position{
          line: start_position.line,
          character: start_position.character
        },
        end: %GenLSP.Structures.Position{
          line: end_position.line,
          character: end_position.character
        }
      }
    }
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true
        attr :kind, :atom, values: [:primary, :secondary]

        slot :inner_block do
          attr :class, :string
        end

        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end

        attr :enabled, :boolean, values: [true, false]

        def toggle(assigns) do
          ~H\"\"\"
          <button><%= @enabled %></button>
          \"\"\"
        end
      end

      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive.Index, :index
          live "/products/:id", ProductLive.Show, :show
        end
      end

      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("save", %{}, socket) do
          {:noreply, socket}
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp controller_facts(template) do
    {:ok, facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        def index(conn, _params) do
          render(conn, :#{template})
        end
      end
      """)

    facts
  end

  defp live_event_scope_facts(template_source) do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Admin.ProductLive do
        use Phoenix.LiveView

        def handle_event("save-admin", _params, socket) do
          {:noreply, socket}
        end
      end

      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("save-product", _params, socket) do
          {:noreply, socket}
        end
      end
      """)

    facts ++ Template.facts(@live_template_uri, template_source)
  end

  defp upload_facts(template_source) do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
        end

        def handle_event("save", _params, socket), do: {:noreply, socket}
        def handle_event("validate", _params, socket), do: {:noreply, socket}
      end
      """)

    facts ++ Template.upload_usage_facts(@live_template_uri, template_source)
  end

  defp non_live_navigation_facts(template_source) do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive, :index
          get "/login", SessionController, :new
        end
      end
      """)

    facts ++ Template.facts(@live_template_uri, template_source)
  end

  defp hook_facts(template_source) do
    AssetHooks.facts(
      "file:///tmp/app/priv/static/assets/app.js",
      """
      const Hooks = {}
      Hooks.PhoneNumber = {
        mounted() {}
      }
      """,
      %{source: :static_asset}
    ) ++ Template.hook_usage_facts(@live_template_uri, template_source)
  end

  defp live_navigation_facts(template_source) do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", live_navigation_router())

    facts ++
      Template.facts(@live_template_uri, template_source) ++ live_navigation_live_view_facts()
  end

  defp live_navigation_source_facts(source) do
    {:ok, source_facts} = ElixirSource.facts(@uri, source)

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", live_navigation_router())

    source_facts ++ route_facts
  end

  defp non_live_source_navigation_facts(source) do
    {:ok, source_facts} = ElixirSource.facts(@uri, source)

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive, :index
          get "/login", SessionController, :new
        end
      end
      """)

    source_facts ++ route_facts
  end

  defp dynamic_source_navigation_facts(source) do
    {:ok, source_facts} = ElixirSource.facts(@uri, source)

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products/:id", ProductLive, :show
        end
      end
      """)

    source_facts ++ route_facts
  end

  defp overlapping_dynamic_source_navigation_facts(source) do
    {:ok, source_facts} = ElixirSource.facts(@uri, source)

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          get "/products/:id", ProductController, :show
          live "/products/:slug", ProductLive, :show
        end
      end
      """)

    source_facts ++ route_facts
  end

  defp multi_session_navigation_facts(template_source) do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live_session :public do
            live "/products", ProductLive, :index
          end

          live_session :admin do
            live "/admin/products", ProductLive, :admin
            live "/admin/settings", SettingsLive, :index
          end
        end
      end
      """)

    facts ++ Template.facts(@live_template_uri, template_source)
  end

  defp admin_template_navigation_facts(template_source) do
    root = System.unique_integer([:positive])
    tmp_root = Path.join(System.tmp_dir!(), "phoenix-ls-navigation-#{root}")
    live_dir = Path.join([tmp_root, "lib", "app_web", "live"])
    template_dir = Path.join(live_dir, "product_live")
    module_path = Path.join(live_dir, "product_live.ex")
    template_path = Path.join(template_dir, "admin.html.heex")

    File.mkdir_p!(template_dir)

    File.write!(module_path, """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      embed_templates "product_live/*"
    end
    """)

    File.write!(template_path, template_source)

    template_uri = "file://" <> template_path

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live_session :public do
            live "/products", ProductLive, :index
          end

          live_session :admin do
            live "/admin/products", ProductLive, :admin
            live "/admin/settings", SettingsLive, :index
          end
        end
      end
      """)

    {template_uri, route_facts ++ Template.facts(template_uri, template_source),
     fn -> File.rm_rf!(tmp_root) end}
  end

  defp live_navigation_live_view_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView
      end

      defmodule AppWeb.OtherLive do
        use Phoenix.LiveView
      end

      defmodule AppWeb.AdminLive do
        use Phoenix.LiveView
      end
      """)

    facts
  end

  defp live_navigation_router do
    """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        live_session :public do
          live "/products", ProductLive, :index
          live "/other-live", OtherLive, :index
        end

        live_session :admin do
          live "/different-session", AdminLive, :index
        end
      end
    end
    """
  end

  defp required_slot_attr_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        slot :item do
          attr :label, :string, required: true
        end

        def list(assigns) do
          ~H\"\"\"
          <div><%= render_slot(@item) %></div>
          \"\"\"
        end
      end
      """)

    facts
  end

  defp slot_scope_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        slot :item do
          attr :class, :string
        end

        def button(assigns) do
          ~H\"\"\"
          <button><%= render_slot(@item) %></button>
          \"\"\"
        end

        slot :item do
          attr :role, :string
        end

        slot :footer

        def card(assigns) do
          ~H\"\"\"
          <section><%= render_slot(@item) %><%= render_slot(@footer) %></section>
          \"\"\"
        end
      end
      """)

    facts
  end

  defp required_slot_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        slot :item, required: true

        def list(assigns) do
          ~H\"\"\"
          <div><%= render_slot(@item) %></div>
          \"\"\"
        end
      end
      """)

    facts
  end

  defp route_helper_facts(source) do
    route_helper_facts(source, """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        live "/products", ProductLive.Index, :index
      end
    end
    """)
  end

  defp route_helper_facts(source, router_source) do
    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, source)
    {:ok, router_facts} = ElixirSource.facts(@uri, router_source)

    controller_facts ++ router_facts
  end

  defp route_facts(router_source) do
    {:ok, facts} = ElixirSource.facts(@uri, router_source)
    facts
  end

  defp imported_page_html_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        import AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp page_html_uses_web_macro_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        use AppWeb, :html
      end
      """)

    facts
  end

  defp web_macro_import_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web.ex", """
      defmodule AppWeb do
        def html do
          quote do
            import AppWeb.CoreComponents
          end
        end
      end
      """)

    facts
  end
end
