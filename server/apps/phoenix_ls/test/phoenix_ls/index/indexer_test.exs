defmodule PhoenixLS.Index.IndexerTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Index.{Indexer, Store}
  alias PhoenixLS.Project.{Engine, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.Document

  @store __MODULE__.Store
  @indexer __MODULE__.Indexer

  setup do
    start_supervised!({Store, name: @store})
    start_supervised!({Indexer, name: @indexer, index_store: @store})

    :ok
  end

  test "asynchronously indexes an open Elixir document" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/page_live.ex",
        "elixir",
        3,
        """
        defmodule AppWeb.PageLive do
          def mount(params, session, socket), do: {:ok, socket}
        end
        """
      )

    assert Indexer.schedule_document(@indexer, document) == :ok

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.PageLive", "AppWeb.PageLive.mount/3"]
    end)
  end

  test "asynchronously indexes an Elixir file from disk by URI", context do
    root = tmp_dir(context)
    path = Path.join([root, "lib", "disk_live.ex"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    defmodule AppWeb.DiskLive do
      def render(assigns), do: assigns
    end
    """)

    assert Indexer.schedule_uri(@indexer, SupportURI.path_to_file_uri!(path)) == :ok

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.DiskLive", "AppWeb.DiskLive.render/1"]
    end)
  end

  test "asynchronously indexes project source files from disk", context do
    root = tmp_dir(context)
    component_path = Path.join([root, "lib", "app_web", "components", "core_components.ex"])

    template_path =
      Path.join([root, "lib", "app_web", "controllers", "page_html", "index.html.heex"])

    File.mkdir_p!(Path.dirname(component_path))
    File.mkdir_p!(Path.dirname(template_path))

    File.write!(component_path, """
    defmodule AppWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button>Save</button>
        \"\"\"
      end
    end
    """)

    File.write!(template_path, "<section><.button /></section>\n")

    assert Indexer.schedule_project(@indexer, SupportURI.path_to_file_uri!(root)) == :ok

    assert_eventually(fn ->
      assert ["AppWeb.CoreComponents.button/1"] =
               @store
               |> Store.by_kind(:component)
               |> Enum.map(& &1.id)

      assert [template] = Store.by_kind(@store, :template)
      assert template.uri == SupportURI.path_to_file_uri!(template_path)
    end)
  end

  test "invalidates facts for deleted uris" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/delete_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.DeleteLive do\nend\n"
      )

    Indexer.schedule_document(@indexer, document)

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.DeleteLive"]
    end)

    assert Indexer.delete_uri(@indexer, document.uri) == :ok

    assert_eventually(fn ->
      assert Store.by_uri(@store, document.uri) == []
    end)
  end

  test "emits telemetry for document, URI, project, and delete jobs", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach_many(
      handler_id,
      [
        [:phoenix_ls, :indexer, :document],
        [:phoenix_ls, :indexer, :uri],
        [:phoenix_ls, :indexer, :project],
        [:phoenix_ls, :indexer, :delete]
      ],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/telemetry_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.TelemetryLive do\nend\n"
      )

    root = tmp_dir(context)
    path = Path.join([root, "lib", "telemetry_disk_live.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule AppWeb.TelemetryDiskLive do\nend\n")
    uri = SupportURI.path_to_file_uri!(path)
    root_uri = SupportURI.path_to_file_uri!(root)

    Indexer.schedule_document(@indexer, document)
    Indexer.schedule_uri(@indexer, uri)
    Indexer.schedule_project(@indexer, root_uri)
    Indexer.delete_uri(@indexer, document.uri)

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :document], %{count: 1},
                    %{uri: "file:///tmp/app/lib/app_web/live/telemetry_live.ex"}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :uri], %{count: 1}, %{uri: ^uri}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :project], %{count: 1},
                    %{root_uri: ^root_uri, result: :ok}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :delete], %{count: 1},
                    %{uri: "file:///tmp/app/lib/app_web/live/telemetry_live.ex"}}
  end

  test "project engines expose a named background indexer" do
    root_uri = "file:///tmp/phoenix-ls-indexer-engine"

    assert {:ok, pid} = Engine.start_link(root_uri: root_uri)
    assert is_pid(pid)
    assert is_pid(GenServer.whereis(Names.indexer(root_uri)))
  end

  defp index_ids(store) do
    store
    |> Store.all()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  def handle_telemetry(event, measurements, metadata, parent) do
    send(parent, {:indexer_telemetry, event, measurements, metadata})
  end

  defp assert_eventually(fun, attempts_left \\ 20)

  defp assert_eventually(fun, attempts_left) do
    fun.()
  rescue
    exception in [ExUnit.AssertionError, MatchError] ->
      if attempts_left > 0 do
        Process.sleep(10)
        assert_eventually(fun, attempts_left - 1)
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp tmp_dir(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_indexer_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
