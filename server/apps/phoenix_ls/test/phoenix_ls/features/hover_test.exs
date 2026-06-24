defmodule PhoenixLS.Features.HoverTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.Hover
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

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

  test "hovers schema form fields" do
    assert_hover("<.input field={@form[:na|me]} />", [
      "field :name, :string",
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

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
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
