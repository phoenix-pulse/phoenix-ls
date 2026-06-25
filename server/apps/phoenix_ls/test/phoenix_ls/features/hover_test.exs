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

  test "hovers remote component attrs through aliases" do
    assert_hover("<CoreComponents.button lab|el=\"Save\" />", [
      "attr :label, :string",
      "required: true",
      "Visible label"
    ])
  end

  test "hovers verified route paths inside ~p sigils" do
    assert_hover("<.link navigate={~p\"/prod|\"} />", [
      "live \"/products/:id\", AppWeb.ProductLive.Show, :show",
      "router AppWeb.Router"
    ])
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
      "schema App.Catalog.Product"
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
      "handle_event(\"select-product\", ...)",
      "AppWeb.ProductLive"
    ])
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

        @doc "Renders a button."
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
