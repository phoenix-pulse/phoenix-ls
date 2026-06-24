defmodule PhoenixLS.Index.DocumentIndexerTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.Position
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

  test "indexes component attr and slot facts from Elixir documents" do
    document =
      document("""
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true

        slot :inner_block do
          attr :class, :string
        end

        def button(assigns) do
          ~H\"\"\"
          <button><%= render_slot(@inner_block) %></button>
          \"\"\"
        end
      end
      """)

    assert DocumentIndexer.index(@store, document) == :ok

    component_id = "AppWeb.CoreComponents.button/1"

    assert [attr_fact] = Store.by_kind(@store, :component_attr)
    assert attr_fact.id == "#{component_id}:attr:label"
    assert attr_fact.data.name == "label"
    assert attr_fact.data.type == :string
    assert attr_fact.data.options == [required: true]

    assert [slot_fact] = Store.by_kind(@store, :component_slot)
    assert slot_fact.id == "#{component_id}:slot:inner_block"
    assert slot_fact.data.name == "inner_block"

    assert [slot_attr_fact] = Store.by_kind(@store, :component_slot_attr)
    assert slot_attr_fact.id == "#{component_id}:slot:inner_block:attr:class"
    assert slot_attr_fact.data.slot == "inner_block"
    assert slot_attr_fact.data.name == "class"
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
        "file:///tmp/app/README.md",
        "markdown",
        1,
        "# App\n"
      )

    assert DocumentIndexer.index(@store, document) == :ignored
    assert Store.all(@store) == []
  end

  test "indexes HEEx template documents into template facts" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex",
        "phoenix-heex",
        4,
        "<section>\n  <.button label=\"Save\" />\n</section>\n"
      )

    assert DocumentIndexer.index(@store, document) == :ok

    assert [template_fact] = Store.by_kind(@store, :template)
    assert template_fact.id == document.uri
    assert template_fact.uri == document.uri
    assert %Position{} = template_fact.range.start
    assert %Position{} = template_fact.range.end
    assert template_fact.range.start.line == 0
    assert template_fact.range.end.line == 3
    assert template_fact.data == %{format: :heex}
    assert template_fact.provenance.document_version == 4
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
