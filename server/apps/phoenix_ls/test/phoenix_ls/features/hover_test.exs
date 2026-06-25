defmodule PhoenixLS.Features.HoverTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.Hover
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

  test "hovers local function component tags" do
    assert_hover("<.button| />", [
      "component AppWeb.CoreComponents.button/1",
      "Renders a button."
    ])
  end

  test "hovers remote function component tags through aliases" do
    assert_hover("<CoreComponents.button| />", [
      "component AppWeb.CoreComponents.button/1",
      "Renders a button."
    ])
  end

  test "hovers component attrs" do
    assert_hover("<.button lab|el=\"Save\" />", [
      "attr :label, :string",
      "required: true",
      "Visible label"
    ])
  end

  test "hovers component slots" do
    assert_hover("<:inner|_block />", [
      "slot :inner_block",
      "required: true",
      "AppWeb.CoreComponents.button/1"
    ])
  end

  test "hovers component slot attrs" do
    assert_hover("<:inner_block cla|ss=\"p-2\" />", [
      "slot attr :class, :string",
      "slot :inner_block",
      "AppWeb.CoreComponents.button/1"
    ])
  end

  test "source-aware slot hovers are scoped to the active component" do
    {source, position} = source_and_position("<.card><:it|em role=\"navigation\" /></.card>")
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover_source(source, position, facts())

    assert String.contains?(value, "slot :item")
    assert String.contains?(value, "AppWeb.CoreComponents.card/1")
    refute String.contains?(value, "AppWeb.CoreComponents.button/1")
  end

  test "source-aware slot attr hovers are scoped to the active component slot" do
    {source, position} = source_and_position("<.card><:item ro|le=\"navigation\" /></.card>")
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover_source(source, position, facts())

    assert String.contains?(value, "slot attr :role, :string")
    assert String.contains?(value, "Card item role")
    assert String.contains?(value, "AppWeb.CoreComponents.card/1")
    refute String.contains?(value, "Button item class")
  end

  test "hovers remote component attrs through aliases" do
    assert_hover("<CoreComponents.button lab|el=\"Save\" />", [
      "attr :label, :string",
      "required: true",
      "Visible label"
    ])
  end

  test "hovers built-in Phoenix component tags and attrs" do
    assert_hover("<.link| navigate={~p\"/products\"}>Products</.link>", [
      "component Phoenix.Component.link/1",
      "LiveView navigation"
    ])

    assert_hover("<.link nav|igate={~p\"/products\"}>Products</.link>", [
      "attr :navigate, :string",
      "Navigates to a LiveView"
    ])
  end

  test "hovers built-in Phoenix components with their attrs in HEEx and H sigils" do
    assert_hover("<.link| navigate={~p\"/products\"}>Products</.link>", [
      "component Phoenix.Component.link/1",
      "Renders a link",
      "attr :navigate, :string",
      "Navigates to a LiveView",
      "attr :replace, :boolean"
    ])

    assert_hover("<.form| for={@form}></.form>", [
      "component Phoenix.Component.form/1",
      "Renders a form tag",
      "attr :for, :any",
      "attr :method, :string",
      "attr :multipart, :boolean"
    ])

    assert_hover("<.live_component| module={AppWeb.RowComponent} id=\"row\" />", [
      "component Phoenix.Component.live_component/1",
      "Renders a stateful LiveComponent",
      "attr :module, :atom",
      "attr :id, :string"
    ])

    assert_hover(
      """
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <.form| for={@form}></.form>
          \"\"\"
        end
      end
      """,
      [
        "component Phoenix.Component.form/1",
        "Renders a form tag",
        "attr :for, :any",
        "attr :method, :string"
      ]
    )
  end

  test "hovers built-in Phoenix component attrs inside H sigils in Elixir source" do
    assert_hover(
      """
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <.link pat|ch={~p"/products"}>Products</.link>
          \"\"\"
        end
      end
      """,
      [
        "attr :patch, :string",
        "Patches the current LiveView"
      ]
    )
  end

  test "hovers source .input components inside H sigils with rich attr docs" do
    {source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents

        def render(assigns) do
          ~H\"\"\"
          <.input| field={@form[:email]} />
          \"\"\"
        end
      end
      """)

    {:ok, context} = CursorContext.at(source, position)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, input_component_facts())

    assert String.contains?(value, "component AppWeb.CoreComponents.input/1")
    assert String.contains?(value, "Renders an input.")
    assert String.contains?(value, "Source: AppWeb.CoreComponents")
    assert String.contains?(value, "attr :field, :any")
    assert String.contains?(value, "required: true")
    assert String.contains?(value, "Form field")
    assert String.contains?(value, "attr :type, :string")
    assert String.contains?(value, ~s(default: "text"))
    assert String.contains?(value, ~s(values: ["text", "email"]))
  end

  test "hovers verified route paths inside ~p sigils" do
    assert_hover("<.link navigate={~p\"/prod|\"} />", [
      "live \"/products/:id\", AppWeb.ProductLive.Show, :show",
      "router AppWeb.Router"
    ])
  end

  test "hovers interpolated verified route paths with the matching route" do
    {source, position} =
      source_and_position(~s(<.link patch={~p"/products/\#{@product}/show/ed|it"} />))

    {:ok, context} = CursorContext.at(source, position)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, route_path_collision_facts())

    assert String.contains?(value, ~s(live "/products/:id/show/edit"))
    assert String.contains?(value, "AppWeb.ProductLive.Show")
    refute String.contains?(value, ~s(live "/products/:id/edit"))
  end

  test "hovers routes with params target and pipelines" do
    {source, position} = source_and_position(~s(<.link navigate={~p"/admin/products/|42"} />))
    {:ok, context} = CursorContext.at(source, position)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, route_hover_detail_facts())

    assert String.contains?(value, ~s(live "/admin/products/:id", AppWeb.ProductLive.Show, :show))
    assert String.contains?(value, "params id")
    assert String.contains?(value, "target AppWeb.ProductLive.Show :show")
    assert String.contains?(value, "pipelines browser, require_user")
  end

  test "hovers route helpers" do
    assert_hover("<p>{Routes.product_pa|th(@socket, :show, 1)}</p>", [
      "live \"/products/:id\", AppWeb.ProductLive.Show, :show",
      "router AppWeb.Router"
    ])
  end

  test "hovers schema form fields" do
    assert_hover("<.input field={@form[:na|me]} />", [
      "field :name, :string",
      "schema App.Catalog.Product"
    ])
  end

  test "hovers schema assigns" do
    assert_hover("<p>{@prod|uct}</p>", [
      ~s(schema "products"),
      "module App.Catalog.Product"
    ])
  end

  test "hovers schema fields through assign property access" do
    assert_hover("<p>{@product.na|me}</p>", [
      "field :name, :string",
      "schema App.Catalog.Product"
    ])
  end

  test "hovers schema associations through assign property access" do
    assert_hover("<p>{@product.acc|ount.name}</p>", [
      "belongs_to :account, App.Accounts.Account",
      "schema App.Catalog.Product",
      "target schema App.Accounts.Account",
      "fields name"
    ])
  end

  test "hovers LiveView assigns" do
    assert_hover("<p>{@selected|_id}</p>", [
      "assign @selected_id",
      "AppWeb.ProductLive"
    ])
  end

  test "hovers LiveView events in phx attributes" do
    assert_hover("<button phx-click=\"select-|product\">", [
      "handle_event(\"select-product\", params, socket)",
      "AppWeb.ProductLive"
    ])
  end

  test "hovers LiveView event handlers with signature and source location" do
    {source, position} = source_and_position(~s(<button phx-click="sa|ve">))
    {:ok, context} = CursorContext.at(source, position)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, event_hover_detail_facts())

    assert String.contains?(value, ~s|handle_event("save", params, socket)|)
    assert String.contains?(value, "module AppWeb.ProductLive")
    assert String.contains?(value, "file /tmp/app/lib/app_web/live/product_live.ex")
    assert String.contains?(value, "location line ")
  end

  test "hovers Phoenix attribute docs" do
    assert_hover("<button phx-cl|ick=\"select-product\">", [
      "phx-click",
      "LiveView click event",
      "Phoenix attribute"
    ])
  end

  test "hovers Phoenix.LiveView.JS commands in phx expressions" do
    {source, position} = source_and_position(~s[<button phx-click={JS.sh|ow(to: "#modal")}>])
    {:ok, context} = CursorContext.at(source, position)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, [])

    assert String.contains?(value, "Phoenix.LiveView.JS.show")
    assert String.contains?(value, "Show elements")
    assert String.contains?(value, "Options: to, transition, time, display, blocking")
    assert String.contains?(value, ~s|Example: `JS.show(to: "#selector")`|)
  end

  test "hovers route helpers in Elixir source files" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_pa|th(conn, :show, 1)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(@controller_uri, position, controller_facts ++ facts())

    assert String.contains?(value, ~s(live "/products/:id", AppWeb.ProductLive.Show, :show))
    assert String.contains?(value, "router AppWeb.Router")
  end

  test "hovers source route helpers matching the helper action" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_pa|th(conn, :show, 1)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(
               @controller_uri,
               position,
               controller_facts ++ route_helper_collision_facts()
             )

    assert String.contains?(value, ~s(get "/products/:id", AppWeb.ProductController, :show))
    refute String.contains?(value, ~s(get "/products", AppWeb.ProductController, :index))
  end

  test "hovers controller render template atoms" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def index(conn, _params) do
          render(conn, :in|dex)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    template_facts = Template.facts(@template_uri, "<h1>Index</h1>")
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(@controller_uri, position, controller_facts ++ template_facts)

    assert String.contains?(value, "template index.html.heex")
    assert String.contains?(value, "format :heex")
    assert String.contains?(value, "module AppWeb.PageHTML")
    assert String.contains?(value, "type controller")

    assert String.contains?(
             value,
             "file /tmp/app/lib/app_web/controllers/page_html/index.html.heex"
           )
  end

  test "hovers controller assigns from rendered templates" do
    {template_source, position} = source_and_position("<p>{@pro|duct.name}</p>")
    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover_source(
               @template_uri,
               template_source,
               position,
               controller_template_assign_facts(template_source)
             )

    assert String.contains?(value, "controller assign @product")
    assert String.contains?(value, "AppWeb.PageController#index")
    assert String.contains?(value, "exact")
  end

  test "returns nil outside supported hover contexts" do
    {source, position} = source_and_position("<p>Hello |world</p>")
    {:ok, context} = CursorContext.at(source, position)

    assert HoverFeature.hover(context, facts()) == nil
  end

  defp assert_hover(marked_source, expected_parts) do
    {source, position} = source_and_position(marked_source)
    {:ok, context} = CursorContext.at(source, position)

    markdown = MarkupKind.markdown()

    assert %Hover{contents: %{kind: ^markdown, value: value}} =
             HoverFeature.hover(context, facts())

    for expected <- expected_parts do
      assert String.contains?(value, expected)
    end
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true, doc: "Visible label"
        attr :kind, :atom, default: :primary

        slot :inner_block, required: true do
          attr :class, :string
        end

        slot :item do
          attr :class, :string, doc: "Button item class"
        end

        @doc "Renders a button."
        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end

        slot :item do
          attr :role, :string, doc: "Card item role"
        end

        def card(assigns) do
          ~H\"\"\"
          <section><%= render_slot(@item) %></section>
          \"\"\"
        end
      end

      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products/:id", ProductLive.Show, :show
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

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp route_helper_collision_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          get "/products", ProductController, :index
          get "/products/:id", ProductController, :show
        end
      end
      """)

    facts
  end

  defp route_path_collision_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products/:id/edit", ProductLive.Index, :edit
          live "/products/:id/show/edit", ProductLive.Show, :edit
        end
      end
      """)

    facts
  end

  defp route_hover_detail_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/admin", AppWeb do
          pipe_through [:browser, :require_user]

          live "/products/:id", ProductLive.Show, :show
        end
      end
      """)

    facts
  end

  defp input_component_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :field, :any, required: true, doc: "Form field"
        attr :type, :string, default: "text", values: ~w(text email)

        @doc "Renders an input."
        def input(assigns) do
          ~H\"\"\"
          <input type={@type} />
          \"\"\"
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp event_hover_detail_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/live/product_live.ex", """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("save", params, socket) do
          {:noreply, socket}
        end
      end
      """)

    facts
  end

  defp controller_template_assign_facts(template_source) do
    {:ok, controller_facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        use Phoenix.Controller

        def index(conn, _params) do
          product = %{name: "Desk"}
          render(assign(conn, :product, product), :index)
        end
      end
      """)

    controller_facts ++ Template.facts(@template_uri, template_source)
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, position}
  end

  defp marker_offset!(marked_source) do
    marked_source
    |> :binary.matches("|")
    |> case do
      [{offset, 1}] -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end
end
