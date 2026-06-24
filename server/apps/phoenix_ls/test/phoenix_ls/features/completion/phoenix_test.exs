defmodule PhoenixLS.Features.Completion.PhoenixTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.CompletionItemKind
  alias PhoenixLS.Features.Completion.Phoenix
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

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

  test "completes schema fields in form field expressions" do
    items = complete("<.input field={@form[:na|]} />")

    assert Enum.map(items, & &1.label) == ["name"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "field :name, :string"
    assert item.insert_text == "name"
  end

  test "completes assigns in HEEx expressions" do
    items = complete("<p>{@sele|}</p>")

    assert Enum.map(items, & &1.label) == ["@selected_id"]

    assert [item] = items
    assert item.kind == CompletionItemKind.variable()
    assert item.insert_text == "@selected_id"
  end

  test "completes LiveView event names in phx attributes" do
    items = complete("<button phx-click=\"sel|\">")

    assert Enum.map(items, & &1.label) == ["select-product"]

    assert [item] = items
    assert item.kind == CompletionItemKind.event()
    assert item.detail == "handle_event(\"select-product\", ...)"
  end

  test "completes small HTML and Phoenix snippets" do
    assert [html_item] = complete("<di|>")
    assert html_item.label == "div"
    assert html_item.kind == CompletionItemKind.snippet()

    phx_items = complete("<button phx-|>")

    assert Enum.map(phx_items, & &1.label) == [
             "phx-click",
             "phx-change",
             "phx-submit",
             "phx-target",
             "phx-value-"
           ]

    phx_item = hd(phx_items)
    assert phx_item.kind == CompletionItemKind.property()
  end

  test "falls back to a narrow generic Elixir completion list" do
    items = complete("<p>{to_s|}</p>")

    assert Enum.map(items, & &1.label) == ["to_string"]
    assert hd(items).kind == CompletionItemKind.function()
  end

  defp complete(marked_source) do
    {source, position} = source_and_position(marked_source)
    {:ok, context} = CursorContext.at(source, position)

    Phoenix.complete(context, facts())
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
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
