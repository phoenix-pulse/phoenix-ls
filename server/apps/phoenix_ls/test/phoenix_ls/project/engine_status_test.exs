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

  test "reports ensured engines with configured compilation-aware mode" do
    %{manager: manager} =
      start_manager(__MODULE__.CompilationAwareSupervisor, __MODULE__.CompilationAwareManager)

    root_uri = "file:///tmp/phoenix-ls-status-compilation-aware"

    assert {:ok, engine} = Manager.ensure_engine(manager, root_uri, source_only?: false)

    assert Manager.status(manager, root_uri) == %EngineStatus{
             root_uri: root_uri,
             state: :running,
             source_only?: false,
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

  test "failed engine starts enter degraded backoff and emit telemetry" do
    root_uri = "file:///tmp/phoenix-ls-status-backoff"

    manager =
      start_supervised!(
        {Manager,
         name: __MODULE__.BackoffManager,
         engine_supervisor: __MODULE__.MissingEngineSupervisor,
         restart_backoff_ms: 500}
      )

    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :project, :degraded],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, _reason} = Manager.ensure_engine(manager, root_uri)

    assert %EngineStatus{state: :degraded, reason: first_reason} =
             Manager.status(manager, root_uri)

    assert_receive {:project_degraded, %{count: 1}, %{root_uri: ^root_uri, reason: ^first_reason}}

    assert {:error, {:backoff, ^first_reason}} = Manager.ensure_engine(manager, root_uri)
    assert Manager.status(manager, root_uri).state == :degraded
  end

  test "failed engine starts publish structured degraded status" do
    root_uri = "file:///tmp/phoenix-ls-status-structured-degraded"

    manager =
      start_supervised!(
        {Manager,
         name: __MODULE__.StructuredStatusManager,
         engine_supervisor: __MODULE__.MissingStructuredStatusSupervisor,
         restart_backoff_ms: 500}
      )

    assert {:error, reason} =
             Manager.ensure_engine(manager, root_uri, status_target: self(), source_only?: false)

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "project",
                      "state" => "degraded",
                      "rootUri" => ^root_uri,
                      "sourceOnly" => false,
                      "reason" => reason_text
                    }},
                   500

    assert reason_text == inspect(reason)
  end

  test "restart_engine reports timeout when stale registry entries cannot unregister" do
    %{manager: manager, supervisor: supervisor} =
      start_manager(__MODULE__.TimeoutSupervisor, __MODULE__.TimeoutManager,
        unregister_timeout_ms: 1
      )

    root_uri = "file:///tmp/phoenix-ls-status-timeout"
    owner = register_stale_engine(root_uri)

    on_exit(fn ->
      send(owner, :stop)
    end)

    assert {:error, :unregister_timeout} = Manager.restart_engine(manager, root_uri)

    assert Manager.status(manager, root_uri) == %EngineStatus{
             root_uri: root_uri,
             state: :degraded,
             source_only?: true,
             reason: :unregister_timeout
           }

    assert DynamicSupervisor.which_children(supervisor) == []
  end

  def handle_telemetry([:phoenix_ls, :project, :degraded], measurements, metadata, parent) do
    send(parent, {:project_degraded, measurements, metadata})
  end

  defp start_manager(supervisor_name, manager_name) do
    start_manager(supervisor_name, manager_name, [])
  end

  defp start_manager(supervisor_name, manager_name, manager_opts) do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})

    manager_opts =
      Keyword.merge([name: manager_name, engine_supervisor: supervisor_name], manager_opts)

    manager = start_supervised!({Manager, manager_opts})

    %{manager: manager, supervisor: supervisor_name}
  end

  defp register_stale_engine(root_uri) do
    parent = self()

    spawn_link(fn ->
      {:ok, _} = Registry.register(PhoenixLS.Project.Registry, {:engine, root_uri}, nil)
      send(parent, :stale_engine_registered)

      receive do
        :stop -> :ok
      end
    end)
    |> tap(fn _pid -> assert_receive :stale_engine_registered end)
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
