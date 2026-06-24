defmodule PhoenixLS.Workspace.FileWatcherTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.{Manager, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.FileWatcher

  defmodule FakeFileSystem do
    def start_link(opts) do
      parent = Keyword.fetch!(opts, :parent)
      send(parent, {:file_system_started, Keyword.fetch!(opts, :dirs)})
      Agent.start_link(fn -> parent end)
    end

    def subscribe(worker) do
      parent = Agent.get(worker, & &1)
      send(parent, {:file_system_subscribed, worker})
      :ok
    end
  end

  test "starts a file_system worker and forwards file events into indexing", context do
    supervisor_name =
      Module.concat(__MODULE__, :"Supervisor#{System.unique_integer([:positive])}")

    manager_name = Module.concat(__MODULE__, :"Manager#{System.unique_integer([:positive])}")

    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    root = fixture_project(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    path = Path.join([root, "lib", "watch_live.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule AppWeb.WatchLive do\nend\n")

    assert {:ok, watcher} =
             FileWatcher.start_link(
               dirs: [root],
               project_manager: manager,
               file_system: FakeFileSystem,
               file_system_opts: [parent: self()]
             )

    assert_receive {:file_system_started, [^root]}
    assert_receive {:file_system_subscribed, _worker}

    send(watcher, {:file_event, self(), {path, [:modified]}})

    assert_eventually(fn ->
      assert is_pid(GenServer.whereis(Names.index_store(root_uri)))

      assert ["AppWeb.WatchLive"] =
               Names.index_store(root_uri)
               |> IndexStore.all()
               |> Enum.map(& &1.id)
    end)
  end

  defp fixture_project(context) do
    root =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_file_watcher_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule FileWatcherFixture.MixProject do
      use Mix.Project

      def project do
        [app: :file_watcher_fixture, version: "0.1.0", deps: []]
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
