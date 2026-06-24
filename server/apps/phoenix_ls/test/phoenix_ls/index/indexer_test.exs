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
