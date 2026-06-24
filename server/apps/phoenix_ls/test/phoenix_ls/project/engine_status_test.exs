defmodule PhoenixLS.Project.EngineStatusTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Project.{EngineStatus, Manager}

  setup_all do
    ensure_project_registry_started()
  end

  test "reports missing roots without starting an engine" do
    %{manager: manager} = start_manager(__MODULE__.MissingSupervisor, __MODULE__.MissingManager)
    root_uri = "file:///tmp/phoenix-ls-status-missing"

    assert Manager.status(manager, root_uri) == %EngineStatus{
             root_uri: root_uri,
             state: :missing,
             source_only?: true,
             reason: :not_started
           }
  end

  test "reports ensured engines as running in source-only mode" do
    %{manager: manager} = start_manager(__MODULE__.RunningSupervisor, __MODULE__.RunningManager)
    root_uri = "file:///tmp/phoenix-ls-status-running"

    assert {:ok, engine} = Manager.ensure_engine(manager, root_uri)

    assert Manager.status(manager, root_uri) == %EngineStatus{
             root_uri: root_uri,
             state: :running,
             source_only?: true,
             pid: engine.pid,
             document_store: engine.document_store,
             index_store: engine.index_store,
             indexer: engine.indexer
           }
  end

  test "dynamic supervisor contains engine crashes and restarts the engine" do
    %{manager: manager} = start_manager(__MODULE__.CrashSupervisor, __MODULE__.CrashManager)
    root_uri = "file:///tmp/phoenix-ls-status-crash"

    assert {:ok, engine} = Manager.ensure_engine(manager, root_uri)
    ref = Process.monitor(engine.pid)
    Process.exit(engine.pid, :kill)

    assert_receive {:DOWN, ^ref, :process, _pid, :killed}

    assert_eventually(fn ->
      assert {:ok, restarted} = Manager.fetch_engine(manager, root_uri)
      assert restarted.pid != engine.pid
      assert Process.alive?(restarted.pid)
    end)
  end

  test "restart_engine explicitly replaces a running engine" do
    %{manager: manager} = start_manager(__MODULE__.RestartSupervisor, __MODULE__.RestartManager)
    root_uri = "file:///tmp/phoenix-ls-status-restart"

    assert {:ok, engine} = Manager.ensure_engine(manager, root_uri)
    assert {:ok, restarted} = Manager.restart_engine(manager, root_uri)

    assert restarted.pid != engine.pid
    assert Manager.status(manager, root_uri).pid == restarted.pid
  end

  defp start_manager(supervisor_name, manager_name) do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    %{manager: manager}
  end

  defp ensure_project_registry_started do
    case Process.whereis(PhoenixLS.Project.Registry) do
      nil ->
        {:ok, pid} = Registry.start_link(keys: :unique, name: PhoenixLS.Project.Registry)

        on_exit(fn ->
          if Process.alive?(pid), do: Process.exit(pid, :normal)
        end)

      _pid ->
        :ok
    end
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
