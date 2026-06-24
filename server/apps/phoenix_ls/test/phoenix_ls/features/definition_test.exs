defmodule PhoenixLS.Features.DefinitionTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.Definition
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  test "goes to local function component definitions" do
    assert_definition("<.button| />", :component, "AppWeb.CoreComponents.button/1")
  end

  test "goes to component attr definitions" do
    assert_definition(
      "<.button lab|el=\"Save\" />",
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

  test "goes to schema field definitions" do
    assert_definition(
      "<.input field={@form[:na|me]} />",
      :schema_field,
      "App.Catalog.Product:schema:products:field:name"
    )
  end

  test "goes to LiveView event definitions from phx attributes" do
    assert_definition(
      "<button phx-click=\"select-|product\">",
      :live_event,
      "AppWeb.ProductLive:event:select-product"
    )
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

        schema "products" do
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
