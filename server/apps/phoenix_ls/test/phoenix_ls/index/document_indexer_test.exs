defmodule PhoenixLS.Index.DocumentIndexerTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Index.{DocumentIndexer, Fact, Store}
  alias PhoenixLS.Workspace.Document

  @store __MODULE__.Store
  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  setup do
    start_supervised!({Store, name: @store})

    :ok
  end

  test "indexes Elixir documents into module and function facts" do
    document =
      document("""
      defmodule AppWeb.PageLive do
        def mount(params, session, socket), do: {:ok, socket}
      end
      """)

    assert DocumentIndexer.index(@store, document) == :ok

    assert @store
           |> Store.all()
           |> Enum.map(& &1.id) == [
             "AppWeb.PageLive.mount/3",
             "AppWeb.PageLive"
           ]
  end

  test "reindexing a uri replaces stale facts" do
    first =
      document("""
      defmodule AppWeb.First do
        def call(socket), do: socket
      end
      """)

    second =
      document("""
      defmodule AppWeb.Second do
        def render(assigns), do: assigns
      end
      """)

    assert DocumentIndexer.index(@store, first) == :ok
    assert DocumentIndexer.index(@store, second) == :ok

    assert @store
           |> Store.all()
           |> Enum.map(& &1.id) == [
             "AppWeb.Second.render/1",
             "AppWeb.Second"
           ]
  end

  test "indexes function component facts from Elixir documents" do
    document =
      document("""
      defmodule AppWeb.CoreComponents do
        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end
      end
      """)

    assert DocumentIndexer.index(@store, document) == :ok

    assert [component_fact] = Store.by_kind(@store, :component)
    assert component_fact.id == "AppWeb.CoreComponents.button/1"
    assert component_fact.uri == @uri
    assert component_fact.data.module == "AppWeb.CoreComponents"
    assert component_fact.data.name == "button"
    assert component_fact.data.type == :function
  end

  test "parse failures clear stale facts for the document uri" do
    assert DocumentIndexer.index(@store, document("defmodule AppWeb.Valid do\nend\n")) == :ok
    assert [_fact] = Store.by_kind(@store, :module)

    broken = document("defmodule AppWeb.Broken do")

    assert {:error, {:parse_error, _reason}} = DocumentIndexer.index(@store, broken)
    assert Store.by_uri(@store, @uri) == []
  end

  test "non-Elixir documents are ignored" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/page.html.heex",
        "phoenix-heex",
        1,
        "<div />"
      )

    assert DocumentIndexer.index(@store, document) == :ignored
    assert Store.all(@store) == []
  end

  test "delete_uri deletes facts for a closed document" do
    fact =
      Fact.new!(
        kind: :module,
        id: "AppWeb.PageLive",
        uri: @uri,
        range: %GenLSP.Structures.Range{
          start: %GenLSP.Structures.Position{line: 0, character: 0},
          end: %GenLSP.Structures.Position{line: 0, character: 1}
        },
        provenance: %{source: :test}
      )

    Store.put(@store, fact)

    assert DocumentIndexer.delete_uri(@store, @uri) == :ok
    assert Store.all(@store) == []
  end

  defp document(text) do
    Document.new(@uri, "elixir", 3, text)
  end
end
