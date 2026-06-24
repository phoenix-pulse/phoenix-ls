defmodule PhoenixLS.Workspace.FileEventsTest do
  use ExUnit.Case, async: false

  alias GenLSP.Enumerations.FileChangeType
  alias GenLSP.Structures.FileEvent
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.{Manager, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.FileEvents

  setup context do
    supervisor_name =
      Module.concat(__MODULE__, :"Supervisor#{System.unique_integer([:positive])}")

    manager_name = Module.concat(__MODULE__, :"Manager#{System.unique_integer([:positive])}")

    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    root = fixture_project(context)

    %{manager: manager, root: root, root_uri: SupportURI.path_to_file_uri!(root)}
  end

  test "changed watched files schedule disk reindexing", %{
    manager: manager,
    root: root,
    root_uri: root_uri
  } do
    path = Path.join([root, "lib", "page_live.ex"])
    write_elixir!(path, "AppWeb.PageLive")
    uri = SupportURI.path_to_file_uri!(path)

    assert FileEvents.handle_lsp_events(manager, [
             %FileEvent{uri: uri, type: FileChangeType.changed()}
           ]) == :ok

    assert_eventually(fn ->
      assert index_ids(Names.index_store(root_uri)) == ["AppWeb.PageLive"]
    end)
  end

  test "deleted watched files invalidate indexed facts", %{
    manager: manager,
    root: root,
    root_uri: root_uri
  } do
    path = Path.join([root, "lib", "gone_live.ex"])
    write_elixir!(path, "AppWeb.GoneLive")
    uri = SupportURI.path_to_file_uri!(path)

    FileEvents.handle_lsp_events(manager, [%FileEvent{uri: uri, type: FileChangeType.changed()}])

    assert_eventually(fn ->
      assert index_ids(Names.index_store(root_uri)) == ["AppWeb.GoneLive"]
    end)

    assert FileEvents.handle_lsp_events(manager, [
             %FileEvent{uri: uri, type: FileChangeType.deleted()}
           ]) == :ok

    assert_eventually(fn ->
      assert IndexStore.by_uri(Names.index_store(root_uri), uri) == []
    end)
  end

  test "non-project uris are ignored", %{manager: manager} do
    assert FileEvents.handle_lsp_events(manager, [
             %FileEvent{uri: "file:///tmp/no-project/file.ex", type: FileChangeType.changed()}
           ]) == :ok
  end

  test "filesystem events normalize to watched-file ingestion", %{
    manager: manager,
    root: root,
    root_uri: root_uri
  } do
    path = Path.join([root, "lib", "fs_live.ex"])
    write_elixir!(path, "AppWeb.FSLive")

    assert FileEvents.handle_file_system_event(manager, path, [:modified]) == :ok

    assert_eventually(fn ->
      assert index_ids(Names.index_store(root_uri)) == ["AppWeb.FSLive"]
    end)

    assert FileEvents.handle_file_system_event(manager, path, [:deleted]) == :ok

    assert_eventually(fn ->
      assert IndexStore.all(Names.index_store(root_uri)) == []
    end)
  end

  defp index_ids(store) do
    store
    |> IndexStore.all()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp write_elixir!(path, module) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule #{module} do\nend\n")
  end

  defp fixture_project(context) do
    root =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_file_events_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule FileEventsFixture.MixProject do
      use Mix.Project

      def project do
        [app: :file_events_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
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
end
