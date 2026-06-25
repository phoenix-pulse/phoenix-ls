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

  test "completes window-level LiveView bindings by prefix" do
    items = complete("<div phx-w|>")

    assert Enum.map(items, & &1.label) == [
             "phx-window-focus",
             "phx-window-blur",
             "phx-window-keydown",
             "phx-window-keyup"
           ]
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

  defp complete(marked_source, marker \\ "|") do
    {source, position} = source_and_position(marked_source, marker)
    {:ok, context} = CursorContext.at(source, position)

    Phoenix.complete(context, facts())
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
