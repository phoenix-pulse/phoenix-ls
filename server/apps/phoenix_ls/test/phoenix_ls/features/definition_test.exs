defmodule PhoenixLS.Features.DefinitionTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.Definition
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Asset.Hooks, as: AssetHooks
  alias PhoenixLS.Introspection.Template
  alias PhoenixLS.Support.Fixtures
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"
  @show_template_uri "file:///tmp/app/lib/app_web/controllers/page_html/show.html.heex"

  test "goes to local function component definitions" do
    assert_definition("<.button| />", :component, "AppWeb.CoreComponents.button/1")
  end

  test "goes to remote function component definitions through aliases" do
    assert_definition("<CoreComponents.button| />", :component, "AppWeb.CoreComponents.button/1")
  end

  test "does not go to local components that are unavailable in the template module" do
    {source, position} = source_and_position("<.but|ton />")
    facts = facts() ++ Template.facts(@template_uri, source)

    assert Definition.definition_source(@template_uri, source, position, facts) == nil
  end

  test "goes to imported local component definitions in template modules" do
    {source, position} = source_and_position("<.but|ton />")

    {:ok, html_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        import AppWeb.CoreComponents
      end
      """)

    expected_fact = Enum.find(facts(), &(&1.id == "AppWeb.CoreComponents.button/1"))
    facts = facts() ++ Template.facts(@template_uri, source) ++ html_facts

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition_source(@template_uri, source, position, facts)
  end

  test "goes to Phoenix web macro imported local component definitions in template modules" do
    {source, position} = source_and_position("<.but|ton />")
    expected_fact = Enum.find(facts(), &(&1.id == "AppWeb.CoreComponents.button/1"))

    facts =
      facts() ++
        Template.facts(@template_uri, source) ++
        page_html_uses_web_macro_facts() ++
        web_macro_import_facts()

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition_source(@template_uri, source, position, facts)
  end

  test "goes to component attr definitions" do
    assert_definition(
      "<.button lab|el=\"Save\" />",
      :component_attr,
      "AppWeb.CoreComponents.button/1:attr:label"
    )
  end

  test "goes to component slot definitions" do
    assert_definition(
      "<:inner|_block />",
      :component_slot,
      "AppWeb.CoreComponents.button/1:slot:inner_block"
    )
  end

  test "goes to component slot attr definitions" do
    assert_definition(
      "<:inner_block cla|ss=\"p-2\" />",
      :component_slot_attr,
      "AppWeb.CoreComponents.button/1:slot:inner_block:attr:class"
    )
  end

  test "source-aware slot definitions are scoped to the active component" do
    assert_source_definition(
      "<.card><:it|em role=\"navigation\" /></.card>",
      :component_slot,
      "AppWeb.CoreComponents.card/1:slot:item"
    )
  end

  test "source-aware slot attr definitions are scoped to the active component slot" do
    assert_source_definition(
      "<.card><:item ro|le=\"navigation\" /></.card>",
      :component_slot_attr,
      "AppWeb.CoreComponents.card/1:slot:item:attr:role"
    )
  end

  test "source-aware generated component definitions use the full tag under the cursor" do
    assert_source_definition(
      "<.hea|der>Product</.header>",
      :component,
      "AppWeb.CoreComponents.header/1",
      Fixtures.generated_core_component_facts()
    )
  end

  test "source-aware generated slot definitions are scoped to the active component" do
    assert_source_definition(
      """
      <.header>
        <:sub|title>This is a product record.</:subtitle>
      </.header>
      """,
      :component_slot,
      "AppWeb.CoreComponents.header/1:slot:subtitle",
      Fixtures.generated_core_component_facts()
    )

    assert_source_definition(
      """
      <.list>
        <:it|em title="Title">Value</:item>
      </.list>
      """,
      :component_slot,
      "AppWeb.CoreComponents.list/1:slot:item",
      Fixtures.generated_core_component_facts()
    )
  end

  test "source-aware generated slot attr definitions are scoped to the active component slot" do
    assert_source_definition(
      """
      <.list>
        <:item tit|le="Title">Value</:item>
      </.list>
      """,
      :component_slot_attr,
      "AppWeb.CoreComponents.list/1:slot:item:attr:title",
      Fixtures.generated_core_component_facts()
    )
  end

  test "goes to remote component attr definitions through aliases" do
    assert_definition(
      "<CoreComponents.button lab|el=\"Save\" />",
      :component_attr,
      "AppWeb.CoreComponents.button/1:attr:label"
    )
  end

  test "goes to verified route definitions inside ~p sigils" do
    assert_definition(
      "<.link navigate={~p\"/prod|\"} />",
      :route,
      "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show"
    )
  end

  test "goes to interpolated verified route definitions using the matching route" do
    {source, position} =
      source_and_position(~s(<.link patch={~p"/products/\#{@product}/show/ed|it"} />))

    router_facts = route_path_collision_facts()

    show_edit_route =
      Enum.find(
        router_facts,
        &(&1.kind == :route and
            &1.id ==
              "AppWeb.Router:live:/products/:id/show/edit:AppWeb.ProductLive.Show:edit")
      )

    assert %Location{uri: @uri, range: show_edit_route.range} ==
             Definition.definition_source(source, position, router_facts)
  end

  test "goes to route definitions from route helpers" do
    assert_definition(
      "<p>{Routes.product_pa|th(@socket, :show, 1)}</p>",
      :route,
      "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show"
    )
  end

  test "goes to schema field definitions" do
    assert_definition(
      "<.input field={@form[:na|me]} />",
      :schema_field,
      "App.Catalog.Product:schema:products:field:name"
    )
  end

  test "goes to schema definitions from assigns" do
    assert_definition(
      "<p>{@prod|uct}</p>",
      :schema,
      "App.Catalog.Product:schema:products"
    )
  end

  test "goes to schema field definitions through assign property access" do
    assert_definition(
      "<p>{@product.na|me}</p>",
      :schema_field,
      "App.Catalog.Product:schema:products:field:name"
    )
  end

  test "goes to schema association definitions through assign property access" do
    assert_definition(
      "<p>{@product.acc|ount.name}</p>",
      :schema_association,
      "App.Catalog.Product:schema:products:association:account"
    )
  end

  test "goes to LiveView event definitions from phx attributes" do
    assert_definition(
      "<button phx-click=\"select-|product\">",
      :live_event,
      "AppWeb.ProductLive:event:select-product"
    )
  end

  test "goes from phx-hook values to JavaScript hook definitions" do
    source = ~s(<div phx-hook="Phone|Number"></div>)
    {source, position} = source_and_position(source)
    facts = hook_facts(source)
    expected_fact = Enum.find(facts, &(&1.kind == :hook and &1.data.name == "PhoneNumber"))

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition(@template_uri, position, facts)
  end

  test "goes from controller render template atoms to HEEx templates" do
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
    template_fact = Enum.find(template_facts, &(&1.kind == :template))

    assert %Location{uri: @template_uri, range: template_fact.range} ==
             Definition.definition(@controller_uri, position, controller_facts ++ template_facts)
  end

  test "ignores nested commas before controller render template atoms" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def show(conn, %{"id" => id}) do
          product = App.Catalog.get_product!(id)
          render(assign(conn, :product, product), :sh|ow)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    template_facts = Template.facts(@show_template_uri, "<h1>Show</h1>")
    template_fact = Enum.find(template_facts, &(&1.kind == :template))

    assert %Location{uri: @show_template_uri, range: template_fact.range} ==
             Definition.definition(@controller_uri, position, controller_facts ++ template_facts)
  end

  test "goes from controller template assigns to controller assign facts" do
    {template_source, position} = source_and_position("<p>{@pro|duct.name}</p>")
    facts = controller_template_assign_facts(template_source)

    expected_fact =
      Enum.find(facts, &(&1.kind == :controller_assign and &1.data.name == "product"))

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition_source(@template_uri, template_source, position, facts)
  end

  test "goes from controller template assign fields to schema field facts" do
    {template_source, position} = source_and_position("<p>{@current_user.em|ail}</p>")
    facts = controller_schema_assign_facts(template_source)

    expected_fact =
      Enum.find(facts, &(&1.kind == :schema_field and &1.data.name == "email"))

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition_source(@template_uri, template_source, position, facts)
  end

  test "goes from controller route helpers to router definitions" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_pa|th(conn, :show, 1)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    router_facts = facts()
    route_fact = Enum.find(router_facts, &(&1.kind == :route))

    assert %Location{uri: @uri, range: route_fact.range} ==
             Definition.definition(@controller_uri, position, controller_facts ++ router_facts)
  end

  test "goes from source route helpers to definitions matching the helper action" do
    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_pa|th(conn, :show, 1)
        end
      end
      """)

    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, controller_source)
    router_facts = route_helper_collision_facts()

    show_route =
      Enum.find(
        router_facts,
        &(&1.kind == :route and
            &1.id ==
              "AppWeb.Router:get:/products/:id:AppWeb.ProductController:show")
      )

    assert %Location{uri: @uri, range: show_route.range} ==
             Definition.definition(@controller_uri, position, controller_facts ++ router_facts)
  end

  test "returns nil outside supported definition contexts" do
    {source, position} = source_and_position("<p>Hello |world</p>")
    {:ok, context} = CursorContext.at(source, position)

    assert Definition.definition(context, facts()) == nil
  end

  defp assert_definition(marked_source, kind, id) do
    {source, position} = source_and_position(marked_source)
    {:ok, context} = CursorContext.at(source, position)

    expected_fact = Enum.find(facts(), &(&1.kind == kind and &1.id == id))

    assert %Location{uri: @uri, range: expected_fact.range} ==
             Definition.definition(context, facts())
  end

  defp assert_source_definition(marked_source, kind, id) do
    assert_source_definition(marked_source, kind, id, facts())
  end

  defp assert_source_definition(marked_source, kind, id, facts) do
    {source, position} = source_and_position(marked_source)
    expected_fact = Enum.find(facts, &(&1.kind == kind and &1.id == id))

    assert %Location{uri: expected_fact.uri, range: expected_fact.range} ==
             Definition.definition_source(source, position, facts)
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true

        slot :inner_block, required: true do
          attr :class, :string
        end

        slot :item do
          attr :class, :string
        end

        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end

        slot :item do
          attr :role, :string
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
    ) ++ Template.hook_usage_facts(@template_uri, template_source)
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
        end
      end
      """)

    controller_facts ++ schema_facts ++ Template.facts(@template_uri, template_source)
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
