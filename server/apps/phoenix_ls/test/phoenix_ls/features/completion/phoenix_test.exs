defmodule PhoenixLS.Features.Completion.PhoenixTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.CompletionItemKind

  import PhoenixLS.Support.LSPConfigHelpers, only: [companion_config: 0, full_config: 0]

  alias PhoenixLS.Features.Completion.Phoenix
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Asset.Hooks, as: AssetHooks
  alias PhoenixLS.Introspection.Template
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"
  @show_template_uri "file:///tmp/app/lib/app_web/controllers/page_html/show.html.heex"
  @other_template_uri "file:///tmp/app/lib/app_web/controllers/admin_html/index.html.heex"
  @live_template_uri "file:///tmp/app/lib/app_web/live/product_live.html.heex"

  test "completes verified route paths inside ~p sigils" do
    items = complete("<.link navigate={~p\"/prod|\"} />")

    assert Enum.map(items, & &1.label) == ["/products/:id"]

    assert [item] = items
    assert item.kind == CompletionItemKind.reference()
    assert item.detail == "live AppWeb.ProductLive.Show :show"
    assert item.insert_text == "/products/:id"

    assert item.data == %{
             "kind" => "route",
             "id" => "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show"
           }
  end

  test "completes static asset paths inside ~p sigils" do
    items = complete(~s(<img src={~p"/images/log|"} />))

    assert Enum.map(items, & &1.label) == ["/images/logo.svg"]

    assert [item] = items
    assert item.kind == CompletionItemKind.file()
    assert item.detail == "image asset - 0.0 KB"
    assert item.insert_text == "/images/logo.svg"
    assert item.data == %{"kind" => "asset", "id" => "/images/logo.svg"}
  end

  test "completes route helpers in HEEx expressions" do
    items = complete("<p>{Routes.us|}</p>")

    labels = Enum.map(items, & &1.label)

    assert "user_path" in labels
    assert "user_url" in labels

    user_path = Enum.find(items, &(&1.label == "user_path"))

    assert user_path.kind == CompletionItemKind.function()
    assert user_path.detail == "Routes.user_path"
    assert user_path.insert_text == "user_path(${1:conn_or_socket}, :${2|index,show|}, ${3:id})"
    assert user_path.insert_text_format == 2

    assert user_path.data == %{
             "kind" => "route_helper",
             "helper" => "user_path"
           }
  end

  test "completes route helpers in Elixir Routes prefixes" do
    {source, position} = source_and_position("Routes.admin_re|")

    items = Phoenix.complete(source, position, facts())

    assert Enum.map(items, & &1.label) == ["admin_report_path", "admin_report_url"]
    assert hd(items).insert_text == "admin_report_path(${1:conn_or_socket}, :${2:index})"
  end

  test "source-aware route helper completion ignores incomplete HEEx route sigils" do
    {source, position} = source_and_position("<.link navigate={~p\"/prod|\"} />")

    assert Phoenix.complete(source, position, facts()) == []
  end

  test "source-aware completion completes verified route paths inside Elixir ~p sigils" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        use AppWeb, :controller

        def index(conn, _params) do
          redirect(conn, to: ~p"/prod|")
        end
      end
      """)

    items = Phoenix.complete(@controller_uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["/products/:id"]

    assert [item] = items
    assert item.kind == CompletionItemKind.reference()
    assert item.detail == "live AppWeb.ProductLive.Show :show"
    assert item.insert_text == "/products/:id"
  end

  test "completes controller render templates" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def index(conn, _params) do
          render(conn, :i|)
        end
      end
      """)

    items = Phoenix.complete(@controller_uri, source, position, template_facts())

    assert Enum.map(items, & &1.label) == [":index"]

    index = hd(items)

    assert index.kind == CompletionItemKind.value()
    assert index.detail == "Template file: index.html.heex"
    assert index.insert_text == "index"

    assert index.data == %{
             "kind" => "template",
             "template" => "index",
             "format" => "html",
             "uri" => @template_uri
           }
  end

  test "completes schema fields in form field expressions" do
    items = complete("<.input field={@form[:na|]} />")

    assert Enum.map(items, & &1.label) == ["name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :name, :string"
    assert item.insert_text == "name"
  end

  test "completes schema fields for form :let bindings" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={@product}>
        <.input field={f[:na|]} />
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :name, :string"
    assert item.insert_text == "name"
  end

  test "does not leak form :let bindings after the form closes" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={@product}>
      </.form>

      <.input field={f[:na|]} />
      """)

    assert Phoenix.complete(@uri, source, position, facts()) == []
  end

  test "completes schema fields for inputs_for :let bindings" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={@product}>
        <.inputs_for :let={variant_form} field={f[:variants]}>
          <.input field={variant_form[:sk|]} />
        </.inputs_for>
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, nested_form_facts())

    assert Enum.map(items, & &1.label) == ["sku"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :sku, :string"
    assert item.insert_text == "sku"
  end

  test "completes schema fields for Phoenix.Component.to_form bindings" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={Phoenix.Component.to_form(@product)}>
        <.input field={f[:na|]} />
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["name"]
  end

  test "completes schema fields for Phoenix.Component.form bindings" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={Phoenix.Component.form(@product)}>
        <.input field={f[:na|]} />
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["name"]
  end

  test "completes nested embedded schema fields for inputs_for bindings" do
    {source, position} =
      source_and_position("""
      <.form :let={f} for={@product}>
        <.inputs_for :let={metadata_form} field={f[:metadata]}>
          <.input field={metadata_form[:we|]} />
        </.inputs_for>
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, nested_form_facts())

    assert Enum.map(items, & &1.label) == ["weight"]
  end

  test "completes nested association fields through source form paths" do
    {source, position} =
      source_and_position("""
      <.form :let={account_form} for={@product.account}>
        <.input field={account_form[:na|]} />
      </.form>
      """)

    items = Phoenix.complete(@uri, source, position, nested_form_facts())

    assert Enum.map(items, & &1.label) == ["name"]
  end

  test "completes schema fields for form bindings inside H sigils" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <.form :let={f} for={Phoenix.Component.to_form(@product)}>
            <.input field={f[:na|]} />
          </.form>
          \"\"\"
        end
      end
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["name"]
  end

  test "completes assigns in HEEx expressions" do
    items = complete("<p>{@sele|}</p>")

    assert Enum.map(items, & &1.label) == ["@selected_id"]

    assert [item] = items
    assert item.kind == CompletionItemKind.variable()
    assert item.insert_text == "@selected_id"
  end

  test "completes LiveView upload names in uploads assign access" do
    {source, position} = source_and_position("<.live_file_input upload={@uploads.ava|} />")

    items = Phoenix.complete(@live_template_uri, source, position, scoped_upload_facts())

    assert Enum.map(items, & &1.label) == ["avatar"]

    assert [item] = items
    assert item.kind == CompletionItemKind.property()
    assert item.detail == "LiveView upload :avatar"
    assert item.insert_text == "avatar"

    assert item.data == %{
             "kind" => "upload",
             "id" => "AppWeb.ProductLive:upload:avatar"
           }
  end

  test "completes LiveView hook names in literal phx-hook values" do
    {source, position} = source_and_position(~s(<div phx-hook="Pho|"></div>))
    {:ok, context} = CursorContext.at(source, position)

    items = Phoenix.complete(context, hook_facts())

    assert Enum.map(items, & &1.label) == ["PhoneNumber"]

    assert [item] = items
    assert item.kind == CompletionItemKind.property()
    assert item.detail == "LiveView hook PhoneNumber"
    assert item.insert_text == "PhoneNumber"

    assert item.data == %{
             "kind" => "hook",
             "id" => "file:///tmp/app/priv/static/assets/app.js:hook:PhoneNumber"
           }
  end

  test "does not complete LiveView hooks outside phx-hook values" do
    {source, position} = source_and_position(~s(<div class="Pho|"></div>))
    {:ok, context} = CursorContext.at(source, position)

    refute "PhoneNumber" in Enum.map(Phoenix.complete(context, hook_facts()), & &1.label)
  end

  test "source-aware phx-hook completion does not include LiveView event completions" do
    {source, position} = source_and_position(~s(<div phx-hook="Pho|"></div>))

    items = Phoenix.complete(@live_template_uri, source, position, hook_and_event_facts())

    assert Enum.map(items, & &1.label) == ["PhoneNumber"]
    assert [%{data: %{"kind" => "hook"}}] = items
  end

  test "completes colocated asset type module names inside script and style :type expressions" do
    {source, position} =
      source_and_position(~s(<script :type={Phoenix.LiveView.Colocated|}></script>))

    items = Phoenix.complete(@live_template_uri, source, position, [])

    assert Enum.map(items, & &1.label) == [
             "Phoenix.LiveView.ColocatedHook",
             "Phoenix.LiveView.ColocatedJS"
           ]

    assert Enum.map(items, & &1.kind) == [
             CompletionItemKind.module(),
             CompletionItemKind.module()
           ]

    assert Enum.map(items, & &1.data) == [
             %{"kind" => "colocated_asset_type", "type" => "colocated_hook"},
             %{"kind" => "colocated_asset_type", "type" => "colocated_js"}
           ]

    {style_source, style_position} =
      source_and_position(~s(<style :type={Phoenix.LiveView.Colocated|}></style>))

    assert Enum.map(
             Phoenix.complete(@live_template_uri, style_source, style_position, []),
             & &1.label
           ) ==
             ["Phoenix.LiveView.ColocatedCSS"]
  end

  test "completes colocated asset type module names from existing cursor context" do
    {source, position} =
      source_and_position(~s(<script :type={Phoenix.LiveView.Colocated|}></script>))

    {:ok, context} = CursorContext.at(source, position)

    items = Phoenix.complete(context, [])

    assert Enum.map(items, & &1.label) == [
             "Phoenix.LiveView.ColocatedHook",
             "Phoenix.LiveView.ColocatedJS"
           ]

    {style_source, style_position} =
      source_and_position(~s(<style :type={Phoenix.LiveView.Colocated|}></style>))

    {:ok, style_context} = CursorContext.at(style_source, style_position)

    assert Enum.map(Phoenix.complete(style_context, []), & &1.label) == [
             "Phoenix.LiveView.ColocatedCSS"
           ]
  end

  test "source-aware aggregate can reuse an existing cursor context for colocated assets" do
    {source, position} =
      source_and_position(~s(<script :type={Phoenix.LiveView.Colocated|}></script>))

    {:ok, context} = CursorContext.at(source, position)
    misleading_source = String.duplicate(" ", position.character)

    items =
      Phoenix.complete(
        @live_template_uri,
        misleading_source,
        position,
        context,
        [],
        full_config()
      )

    assert Enum.map(items, & &1.label) == [
             "Phoenix.LiveView.ColocatedHook",
             "Phoenix.LiveView.ColocatedJS"
           ]
  end

  test "source-only aggregate excludes hook and colocated context completions" do
    {colocated_source, colocated_position} =
      source_and_position(~s(<script :type={Phoenix.LiveView.Colocated|}></script>))

    assert Phoenix.complete_source_only(
             @live_template_uri,
             colocated_source,
             colocated_position,
             [],
             full_config()
           ) == []

    assert Enum.map(
             Phoenix.complete(@live_template_uri, colocated_source, colocated_position, []),
             & &1.label
           ) == [
             "Phoenix.LiveView.ColocatedHook",
             "Phoenix.LiveView.ColocatedJS"
           ]

    {hook_source, hook_position} = source_and_position(~s(<div phx-hook="Pho|"></div>))

    refute "PhoneNumber" in Enum.map(
             Phoenix.complete_source_only(
               @live_template_uri,
               hook_source,
               hook_position,
               hook_facts(),
               full_config()
             ),
             & &1.label
           )

    assert Enum.map(
             Phoenix.complete(@live_template_uri, hook_source, hook_position, hook_facts()),
             & &1.label
           ) == ["PhoneNumber"]
  end

  test "source-only aggregate can reuse existing cursor context for scoped uploads" do
    {source, position} = source_and_position("<.live_file_input upload={@uploads.|} />")
    {:ok, context} = CursorContext.at(source, position)
    misleading_source = String.duplicate(" ", position.character)

    items =
      Phoenix.complete_source_only(
        @live_template_uri,
        misleading_source,
        position,
        context,
        scoped_upload_facts(),
        full_config()
      )

    assert Enum.map(items, & &1.label) == ["avatar"]
  end

  test "full source-aware aggregate can reuse existing cursor context for scoped uploads" do
    {source, position} = source_and_position("<.live_file_input upload={@uploads.|} />")
    {:ok, context} = CursorContext.at(source, position)
    misleading_source = String.duplicate(" ", position.character)

    items =
      Phoenix.complete(
        @live_template_uri,
        misleading_source,
        position,
        context,
        scoped_upload_facts(),
        full_config()
      )

    assert Enum.map(items, & &1.label) == ["avatar"]
  end

  test "scopes LiveView upload completion to the template module when available" do
    {source, position} = source_and_position("<.live_file_input upload={@uploads.|} />")

    items =
      Phoenix.complete(
        @live_template_uri,
        source,
        position,
        scoped_upload_facts()
      )

    assert Enum.map(items, & &1.label) == ["avatar"]
  end

  test "does not complete LiveView uploads from the unscoped context path" do
    {source, position} = source_and_position("<.live_file_input upload={@uploads.|} />")
    {:ok, context} = CursorContext.at(source, position)

    assert Phoenix.complete(context, scoped_upload_facts()) == []
  end

  test "completes schema fields for assign property access" do
    items = complete("<p>{@product.na|}</p>")

    assert Enum.map(items, & &1.label) == ["name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :name, :string"
    assert item.insert_text == "name"
  end

  test "completes schema associations for assign property access" do
    items = complete("<p>{@product.acc|}</p>")

    assert Enum.map(items, & &1.label) == ["account"]

    assert [item] = items
    assert item.kind == CompletionItemKind.reference()
    assert item.detail == "belongs_to :account, App.Accounts.Account"
    assert item.insert_text == "account"

    assert item.data == %{
             "kind" => "schema_association",
             "id" => "App.Catalog.Product:schema:products:association:account"
           }
  end

  test "completes schema fields for assigns map property access" do
    items = complete("<p>{assigns.product.na|}</p>")

    assert Enum.map(items, & &1.label) == ["name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :name, :string"
    assert item.insert_text == "name"
  end

  test "completes controller render and plug assigns in rendered templates" do
    {source, position} = source_and_position("<p>{@|}</p>")

    items =
      Phoenix.complete(
        @template_uri,
        source,
        position,
        controller_assign_completion_facts(source)
      )

    labels = Enum.map(items, & &1.label)

    assert "@current_user" in labels
    assert "@product" in labels

    assert %{"kind" => "controller_assign", "id" => product_id} =
             Enum.find(items, &(&1.label == "@product")).data

    assert String.starts_with?(
             product_id,
             "AppWeb.PageController:assign:index:product:"
           )

    assert %{"kind" => "controller_plug_assign", "id" => current_user_id} =
             Enum.find(items, &(&1.label == "@current_user")).data

    assert String.starts_with?(
             current_user_id,
             "AppWeb.PageController:plug_assign:load_current_user:current_user:"
           )
  end

  test "completes schema fields from controller assign source variables" do
    {source, position} = source_and_position("<p>{@current_user.em|}</p>")

    items =
      Phoenix.complete(
        @template_uri,
        source,
        position,
        controller_schema_assign_facts(source)
      )

    assert Enum.map(items, & &1.label) == ["email"]

    {nested_source, nested_position} = source_and_position("<p>{@current_user.account.na|}</p>")

    nested_items =
      Phoenix.complete(
        @template_uri,
        nested_source,
        nested_position,
        controller_schema_assign_facts(nested_source)
      )

    assert Enum.map(nested_items, & &1.label) == ["name"]
  end

  test "completes LiveView event names in phx attributes" do
    items = complete("<button phx-click=\"sel|\">")

    assert Enum.map(items, & &1.label) == ["select-product"]

    assert [item] = items
    assert item.kind == CompletionItemKind.event()
    assert item.detail == "handle_event(\"select-product\", ...)"
  end

  test "completes same-module LiveView event names inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("close-product", _params, socket) do
          {:noreply, socket}
        end

        def render(assigns) do
          ~H\"\"\"
          <button phx-click="clo|">Close</button>
          \"\"\"
        end
      end
      """)

    {:ok, facts} = ElixirSource.facts(@uri, source)

    items = Phoenix.complete(@uri, source, position, facts)

    assert Enum.map(items, & &1.label) == ["close-product"]
  end

  test "completes same-module LiveComponent event names inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.ProductLive.FormComponent do
        use Phoenix.LiveComponent

        def handle_event("validate", _params, socket) do
          {:noreply, socket}
        end

        def render(assigns) do
          ~H\"\"\"
          <.simple_form phx-change="val|"></.simple_form>
          \"\"\"
        end
      end
      """)

    {:ok, facts} = ElixirSource.facts(@uri, source)

    items = Phoenix.complete(@uri, source, position, facts)

    assert Enum.map(items, & &1.label) == ["validate"]
  end

  test "completes temporary assigns inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, socket, temporary_assigns: [notice: nil]}
        end

        def render(assigns) do
          ~H\"\"\"
          <p>{@not|}</p>
          \"\"\"
        end
      end
      """)

    {:ok, facts} = ElixirSource.facts(@uri, source)

    items = Phoenix.complete(@uri, source, position, facts)

    assert Enum.map(items, & &1.label) == ["@notice"]

    assert [item] = items
    assert item.kind == CompletionItemKind.variable()
    assert item.detail == "assign @notice"
  end

  test "completes same-component attrs and slots as assigns inside H sigils" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.AdminComponents do
        use Phoenix.Component

        attr :title, :string, required: true
        attr :value, :any, required: true
        attr :tone, :string, default: "neutral"
        slot :inner_block

        def metric_card(assigns) do
          ~H\"\"\"
          {@|}
          \"\"\"
        end

        attr :entries, :list, default: []

        def audit_timeline(assigns) do
          ~H\"\"\"
          {@entries}
          \"\"\"
        end
      end
      """)

    {:ok, facts} = ElixirSource.facts(@uri, source)

    labels =
      @uri
      |> Phoenix.complete(source, position, facts)
      |> Enum.map(& &1.label)

    assert "@inner_block" in labels
    assert "@title" in labels
    assert "@tone" in labels
    assert "@value" in labels
    refute "@entries" in labels
  end

  test "completes LiveView JS commands in phx expression attributes" do
    items = complete(~s(<button phx-click={JS.|}>))

    labels = Enum.map(items, & &1.label)

    assert "JS.show" in labels
    assert "JS.push" in labels
    assert "JS.toggle_attribute" in labels
    assert "JS.ignore_attributes" in labels

    show = Enum.find(items, &(&1.label == "JS.show"))

    assert show.kind == CompletionItemKind.function()
    assert show.detail == "Show elements"
    assert show.insert_text == "JS.show(to: \"${1:#selector}\")"
    assert show.insert_text_format == 2
    assert show.data == %{"kind" => "live_view_js_command", "name" => "show"}
  end

  test "completes chainable LiveView JS commands after pipe operator" do
    items = complete(~S[<button phx-click={JS.show(to: "#modal") |> §}>], "§")

    labels = Enum.map(items, & &1.label)

    assert "hide" in labels
    assert "focus_first" in labels
    assert "push" in labels
    refute "JS.hide" in labels

    hide = Enum.find(items, &(&1.label == "hide"))

    assert hide.kind == CompletionItemKind.function()
    assert hide.detail == "Hide elements"
    assert hide.insert_text == "hide(to: \"${1:#selector}\")"
    assert hide.insert_text_format == 2
    assert hide.data == %{"kind" => "live_view_js_command", "name" => "hide"}
  end

  test "completes LiveView JS command option names" do
    items = complete(~S[<button phx-click={JS.show(t§)} />], "§")

    assert Enum.map(items, & &1.label) == ["to:", "transition:", "time:"]

    to = hd(items)
    assert to.kind == CompletionItemKind.property()
    assert to.detail == "JS.show option"
    assert to.insert_text == ~s(to: "${1:#selector}")
    assert to.insert_text_format == 2
    assert to.data == %{"kind" => "live_view_js_option", "command" => "show", "name" => "to"}

    push_items = complete(~S[<button phx-click={JS.push("save", val§)} />], "§")

    assert Enum.map(push_items, & &1.label) == ["value:"]
    assert hd(push_items).insert_text == "value: %{${1:key}: ${2:value}}"
  end

  test "ranks Phoenix attrs by element and known LiveView events" do
    {source, position} = source_and_position(~S[<form phx-§>], "§")

    items = Phoenix.complete(@live_template_uri, source, position, hook_and_event_facts())

    assert Enum.take(Enum.map(items, & &1.label), 4) == [
             "phx-submit",
             "phx-change",
             "phx-auto-recover",
             "phx-click"
           ]

    assert Enum.find(items, &(&1.label == "phx-click")).detail ==
             "LiveView event: PhoneHome"

    {input_source, input_position} = source_and_position(~S[<input phx-§>], "§")

    input_items = Phoenix.complete(@live_template_uri, input_source, input_position, facts())

    assert Enum.take(Enum.map(input_items, & &1.label), 4) == [
             "phx-focus",
             "phx-blur",
             "phx-keydown",
             "phx-keyup"
           ]
  end

  test "completes small HTML and Phoenix snippets" do
    assert [html_item] = complete("<di|>")
    assert html_item.label == "div"
    assert html_item.kind == CompletionItemKind.snippet()

    phx_items = complete("<button phx-|>")

    phx_labels = Enum.map(phx_items, & &1.label)

    assert "phx-click" in phx_labels
    assert "phx-target" in phx_labels
    assert "phx-value-" in phx_labels
    assert "phx-mounted" in phx_labels
    assert "phx-window-keydown" in phx_labels

    phx_item = hd(phx_items)
    assert phx_item.kind == CompletionItemKind.property()
  end

  test "completes built-in Phoenix component tags" do
    items = complete("<.|>")
    labels = Enum.map(items, & &1.label)

    assert ".link" in labels
    assert ".live_component" in labels
    assert ".form" in labels
    assert ".inputs_for" in labels
    assert ".live_file_input" in labels

    link = Enum.find(items, &(&1.label == ".link"))
    assert link.kind == CompletionItemKind.function()
    assert link.detail == "Phoenix.Component.link/1"
    assert link.insert_text == ".link"
    assert link.data == %{"kind" => "phoenix_component", "id" => "Phoenix.Component.link/1"}
  end

  test "completes built-in Phoenix component attrs" do
    items = complete("<.link |></.link>")
    labels = Enum.map(items, & &1.label)

    assert "href" in labels
    assert "navigate" in labels
    assert "patch" in labels
    assert "replace" in labels
    assert "method" in labels
    assert "csrf_token" in labels
    assert "download" in labels
    assert "class" in labels
    assert "phx-click" in labels

    navigate = Enum.find(items, &(&1.label == "navigate"))
    assert navigate.kind == CompletionItemKind.property()
    assert navigate.detail == "attr :navigate, :string"
    assert navigate.insert_text == ~s(navigate={${1:~p"/path"}})
    assert navigate.insert_text_format == 2

    assert navigate.data == %{
             "kind" => "phoenix_component_attr",
             "id" => "Phoenix.Component.link/1:attr:navigate"
           }
  end

  test "completes built-in Phoenix component attrs inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <.link |></.link>
          \"\"\"
        end
      end
      """)

    {:ok, context} = CursorContext.at(source, position)

    labels =
      context
      |> Phoenix.complete(facts())
      |> Enum.map(& &1.label)

    assert "href" in labels
    assert "navigate" in labels
    assert "patch" in labels
    assert "class" in labels
    assert "phx-click" in labels
  end

  test "completes HEEx special attributes" do
    items = complete("<div :|>")

    assert Enum.map(items, & &1.label) == [":for", ":if", ":let", ":key"]

    for_item = hd(items)

    assert for_item.kind == CompletionItemKind.property()
    assert for_item.detail == "HEEx comprehension"
    assert for_item.insert_text == ":for={${1:item} <- ${2:@items}}"
    assert for_item.insert_text_format == 2
    assert for_item.data == %{"kind" => "heex_special_attr", "id" => ":for"}
  end

  test "completes non-colon HEEx special attributes" do
    items = complete("<div phx-no|>")

    assert "phx-no-format" in Enum.map(items, & &1.label)

    item = Enum.find(items, &(&1.label == "phx-no-format"))
    assert item.kind == CompletionItemKind.property()
    assert item.detail == "Disable HEEx formatter for this element"
    assert item.insert_text == "phx-no-format"
    assert item.data == %{"kind" => "heex_special_attr", "id" => "phx-no-format"}
  end

  test "completes HEEx special attributes inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <div :|>
          \"\"\"
        end
      end
      """)

    labels =
      @uri
      |> Phoenix.complete(source, position, facts())
      |> Enum.map(& &1.label)

    assert [":for", ":if", ":let", ":key"] = labels
  end

  test "completes window-level LiveView bindings by prefix" do
    items = complete("<div phx-w|>")

    assert Enum.map(items, & &1.label) == [
             "phx-window-focus",
             "phx-window-blur",
             "phx-window-keydown",
             "phx-window-keyup"
           ]
  end

  test "completes phx-value attributes from :for loop schema fields" do
    {source, position} =
      source_and_position("""
      <div :for={product <- @products}>
        <button phx-click="select" phx-value-na|>
      </div>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["phx-value-name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.property()
    assert item.detail == "From product: :string"
    assert item.insert_text == "phx-value-name={product.name}"
  end

  test "completes scoped :for variables in HEEx expressions" do
    {source, position} =
      source_and_position("""
      <div :for={product <- @products}>
        {pro|}
      </div>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["product"]

    assert [item] = items
    assert item.kind == CompletionItemKind.variable()
    assert item.detail == "HEEx :for binding"
    assert item.insert_text == "product"
    assert item.data == %{"kind" => "heex_scoped_variable", "name" => "product"}
  end

  test "completes scoped :for variables inside H sigils in Elixir source" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <div :for={product <- @products}>
            {pro|}
          </div>
          \"\"\"
        end
      end
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["product"]
  end

  test "completes phx-value attributes from tuple :for loop schema fields" do
    {source, position} =
      source_and_position("""
      <div :for={{_row_id, product} <- @products}>
        <button phx-click="select" phx-value-na|>
      </div>
      """)

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == ["phx-value-name"]
    assert hd(items).insert_text == "phx-value-name={product.name}"
  end

  test "completes Phoenix shortcut snippets with replacement edits" do
    {source, position} = source_and_position(".live|")

    items = Phoenix.complete(@uri, source, position, facts())

    assert Enum.map(items, & &1.label) == [".live"]

    assert [item] = items
    assert item.kind == CompletionItemKind.snippet()
    assert item.detail == "Phoenix component shortcut"
    assert item.text_edit.new_text == ~s(<.live_component module={${1:Module}} id="${2:id}" />)
    assert item.text_edit.range.start.line == 0
    assert item.text_edit.range.start.character == 0
    assert item.text_edit.range.end.character == 5
  end

  test "completes Phoenix pattern and event shortcut snippets" do
    {form_source, form_position} = source_and_position("form.phx|")
    form_items = Phoenix.complete(@uri, form_source, form_position, facts())

    assert [form] = form_items
    assert form.label == "form.phx"
    assert form.text_edit.new_text =~ ~s(<form phx-submit="${1:save}">)

    {event_source, event_position} = source_and_position("<button @click|>")
    event_items = Phoenix.complete(@uri, event_source, event_position, facts())

    assert [event] = event_items
    assert event.label == "@click"
    assert event.kind == CompletionItemKind.event()
    assert event.text_edit.new_text == ~s(phx-click="${1:action}")
  end

  test "completes element-specific HTML attributes" do
    items = complete("<img s|>")
    labels = Enum.map(items, & &1.label)

    assert "src" in labels
    assert "srcset" in labels
    assert "sizes" in labels

    src = Enum.find(items, &(&1.label == "src"))

    assert src.kind == CompletionItemKind.property()
    assert src.detail == "Image URL"
    assert src.insert_text == "src=\"${1:value}\""
    assert src.insert_text_format == 2
    assert src.data == %{"kind" => "html_attr", "tag" => "img", "name" => "src"}
  end

  test "completes predefined HTML attribute values" do
    items = complete(~s(<input type="em|">))

    assert Enum.map(items, & &1.label) == ["email"]

    email = hd(items)

    assert email.kind == CompletionItemKind.value()
    assert email.detail == "type value for <input>"
    assert email.insert_text == "email"

    assert email.data == %{
             "kind" => "html_attr_value",
             "tag" => "input",
             "attribute" => "type",
             "value" => "email"
           }
  end

  test "falls back to a narrow generic Elixir completion list" do
    items = complete("<p>{to_s|}</p>")

    assert Enum.map(items, & &1.label) == ["to_string"]
    assert hd(items).kind == CompletionItemKind.function()
  end

  test "keeps generic Elixir fallback completion in full mode" do
    {source, position} = source_and_position("<p>{to_s|}</p>")
    {:ok, context} = CursorContext.at(source, position)

    items = Phoenix.complete(context, facts(), full_config())

    assert [%{data: %{"kind" => "elixir_fallback"}}] = items
    assert Enum.map(items, & &1.label) == ["to_string"]
  end

  test "omits generic Elixir fallback completion in companion mode" do
    {source, position} = source_and_position("<p>{to_s|}</p>")
    {:ok, context} = CursorContext.at(source, position)

    items = Phoenix.complete(context, facts(), companion_config())

    refute Enum.any?(items, &(&1.data["kind"] == "elixir_fallback"))
    refute "to_string" in Enum.map(items, & &1.label)
  end

  test "keeps Phoenix-specific context completions in companion mode" do
    {source, position} = source_and_position("<p>{Routes.us|}</p>")
    {:ok, context} = CursorContext.at(source, position)

    items = Phoenix.complete(context, facts(), companion_config())

    assert "user_path" in Enum.map(items, & &1.label)

    assert Enum.find(items, &(&1.label == "user_path")).data == %{
             "kind" => "route_helper",
             "helper" => "user_path"
           }
  end

  test "keeps completion contexts active for Phoenix trigger characters" do
    assert "@selected_id" in completion_labels("<p>{@|}</p>")
    assert "JS.show" in completion_labels(~s(<button phx-click={JS.|}>))
    assert [":for", ":if", ":let", ":key"] = completion_labels("<div :|>")
    assert "div" in completion_labels("<di|>")
    assert "/products/:id" in completion_labels(~s(<.link navigate={~p"/|"} />))
    assert "/products/:id" in completion_labels(~s(<.link navigate={~p"|"} />))
    assert "to:" in completion_labels(~S[<button phx-click={JS.show(t|)} />])
    assert "JS.show" in completion_labels(~s(<button phx-click={|}>))
    refute "JS.show" in completion_labels(~s(<button phx-value-id={|}>))
  end

  defp complete(marked_source, facts \\ facts(), marker \\ "|")

  defp complete(marked_source, facts, marker) when is_list(facts) do
    {source, position} = source_and_position(marked_source, marker)
    {:ok, context} = CursorContext.at(source, position)

    Phoenix.complete(context, facts)
  end

  defp complete(marked_source, marker, _default) when is_binary(marker) do
    complete(marked_source, facts(), marker)
  end

  defp completion_labels(marked_source) do
    marked_source
    |> complete()
    |> Enum.map(& &1.label)
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          get "/users", UserController, :index
          get "/users/:id", UserController, :show
          live "/products/:id", ProductLive.Show, :show
        end

        scope "/admin", AppWeb do
          get "/reports", ReportController, :index
        end
      end

      defmodule App.Catalog.Product do
        use Ecto.Schema
        alias App.Accounts.Account

        schema "products" do
          field :name, :string
          belongs_to :account, Account
        end
      end

      defmodule App.Accounts.Account do
        use Ecto.Schema

        schema "accounts" do
          field :name, :string
        end
      end

      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("select-product", %{"id" => id}, socket) do
          {:noreply, assign(socket, :selected_id, id)}
        end
      end
      """)

    facts ++
      [
        PhoenixLS.Index.Fact.new!(
          kind: :asset,
          id: "/images/logo.svg",
          uri: "file:///tmp/app/priv/static/images/logo.svg",
          range: %GenLSP.Structures.Range{
            start: %GenLSP.Structures.Position{line: 0, character: 0},
            end: %GenLSP.Structures.Position{line: 0, character: 0}
          },
          provenance: %{source: :static_asset},
          data: %PhoenixLS.Introspection.Asset.Asset{
            public_path: "/images/logo.svg",
            file_path: "/tmp/app/priv/static/images/logo.svg",
            type: :image,
            size: 11
          }
        )
      ]
  end

  defp controller_assign_completion_facts(template_source) do
    {:ok, controller_facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        use Phoenix.Controller

        plug :load_current_user

        def index(conn, _params) do
          product = %{name: "Desk"}

          render(assign(conn, :product, product), :index)
        end

        defp load_current_user(conn, _opts), do: assign(conn, :current_user, nil)
      end
      """)

    controller_facts ++ Template.facts(@template_uri, template_source)
  end

  defp controller_schema_assign_facts(template_source) do
    {:ok, controller_facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        use Phoenix.Controller

        def index(conn, %{"id" => id}) do
          user = App.Accounts.get_user!(id)

          render(assign(conn, :current_user, user), :index)
        end
      end
      """)

    {:ok, schema_facts} =
      ElixirSource.facts(@uri, """
      defmodule App.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :email, :string
          belongs_to :account, App.Accounts.Account
        end
      end

      defmodule App.Accounts.Account do
        use Ecto.Schema

        schema "accounts" do
          field :name, :string
        end
      end
      """)

    controller_facts ++ schema_facts ++ Template.facts(@template_uri, template_source)
  end

  defp scoped_upload_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
        end
      end

      defmodule AppWeb.AdminLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, allow_upload(socket, :document, accept: ~w(.pdf), max_entries: 1)}
        end
      end
      """)

    facts ++ Template.facts(@live_template_uri, "<div />")
  end

  defp template_facts do
    Template.facts(@template_uri, "<h1>Index</h1>") ++
      Template.facts(@show_template_uri, "<h1>Show</h1>") ++
      Template.facts(@other_template_uri, "<h1>Other</h1>")
  end

  defp nested_form_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule App.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          field :name, :string
          belongs_to :account, App.Accounts.Account
          embeds_one :metadata, Metadata
          has_many :variants, App.Catalog.Variant
        end
      end

      defmodule App.Catalog.Product.Metadata do
        use Ecto.Schema

        embedded_schema do
          field :weight, :integer
        end
      end

      defmodule App.Catalog.Variant do
        use Ecto.Schema

        schema "variants" do
          field :sku, :string
        end
      end

      defmodule App.Accounts.Account do
        use Ecto.Schema

        schema "accounts" do
          field :name, :string
        end
      end
      """)

    facts
  end

  defp hook_facts do
    AssetHooks.facts(
      "file:///tmp/app/priv/static/assets/app.js",
      """
      const Hooks = {}
      Hooks.PhoneNumber = {
        mounted() {}
      }
      Hooks.MapPicker = {
        mounted() {}
      }
      """,
      %{source: :static_asset}
    )
  end

  defp hook_and_event_facts do
    {:ok, event_facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("PhoneHome", _params, socket) do
          {:noreply, socket}
        end
      end
      """)

    hook_facts() ++ event_facts ++ Template.facts(@live_template_uri, "<div />")
  end

  defp source_and_position(marked_source, marker \\ "|") do
    marker_offset = marker_offset!(marked_source, marker)
    source = String.replace(marked_source, marker, "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, position}
  end

  defp marker_offset!(marked_source, marker) do
    marked_source
    |> :binary.matches(marker)
    |> case do
      [{offset, marker_size}] when marker_size == byte_size(marker) -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end
end
