defmodule PhoenixLS.Features.DefinitionTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.Definition
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template
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

  test "goes to component attr definitions" do
    assert_definition(
      "<.button lab|el=\"Save\" />",
      :component_attr,
      "AppWeb.CoreComponents.button/1:attr:label"
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

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true

        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
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
