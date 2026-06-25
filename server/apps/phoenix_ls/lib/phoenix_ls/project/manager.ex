defmodule PhoenixLS.Project.Manager do
  @moduledoc """
  Manager-side API for project engine ownership.
  """

  use GenServer

  alias PhoenixLS.LSP.Status
  alias PhoenixLS.Project.{Engine, EngineStatus, Locator}
  alias PhoenixLS.Support.Telemetry

  @default_name __MODULE__
  @default_engine_supervisor PhoenixLS.Project.EngineSupervisor
  @registry PhoenixLS.Project.Registry
  @default_restart_backoff_ms 1_000
  @default_unregister_timeout_ms 100

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec ensure_engine(GenServer.server(), String.t(), keyword()) ::
          {:ok, Engine.t()} | {:error, term()}
  def ensure_engine(server \\ @default_name, root_uri, opts \\ [])
      when is_binary(root_uri) and is_list(opts) do
    GenServer.call(server, {:ensure_engine, root_uri, opts})
  end

  @spec ensure_project_for_uri(GenServer.server(), String.t(), keyword()) ::
          {:ok, Engine.t()} | :error | {:error, term()}
  def ensure_project_for_uri(server \\ @default_name, uri, opts \\ [])
      when is_binary(uri) and is_list(opts) do
    GenServer.call(server, {:ensure_project_for_uri, uri, opts})
  end

  @spec restart_engine(GenServer.server(), String.t(), keyword()) ::
          {:ok, Engine.t()} | {:error, term()}
  def restart_engine(server \\ @default_name, root_uri, opts \\ [])
      when is_binary(root_uri) and is_list(opts) do
    GenServer.call(server, {:restart_engine, root_uri, opts})
  end

  @spec fetch_engine(GenServer.server(), String.t()) :: {:ok, Engine.t()} | :error
  def fetch_engine(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:fetch_engine, root_uri})
  end

  @spec status(GenServer.server(), String.t()) :: EngineStatus.t()
  def status(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:status, root_uri})
  end

  @spec document_store(GenServer.server(), String.t()) :: {:ok, GenServer.server()} | :error
  def document_store(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:document_store, root_uri})
  end

  @impl true
  def init(opts) do
    state = %{
      engine_supervisor: Keyword.get(opts, :engine_supervisor, @default_engine_supervisor),
      restart_backoff_ms: Keyword.get(opts, :restart_backoff_ms, @default_restart_backoff_ms),
      unregister_timeout_ms:
        Keyword.get(opts, :unregister_timeout_ms, @default_unregister_timeout_ms),
      degraded: %{},
      backoff_until: %{},
      source_only: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:ensure_engine, root_uri, opts}, _from, state) do
    {reply, state} = ensure_engine_started(state, root_uri, opts)

    {:reply, reply, state}
  end

  def handle_call({:ensure_project_for_uri, uri, opts}, _from, state) do
    {reply, state} =
      case Locator.locate(uri) do
        {:ok, located} -> ensure_engine_started(state, located.root_uri, opts)
        :error -> {:error, state}
        {:error, _reason} = error -> {error, state}
      end

    {:reply, reply, state}
  end

  def handle_call({:restart_engine, root_uri, opts}, _from, state) do
    case terminate_engine(state, root_uri) do
      :ok ->
        {reply, state} = start_engine_with_state(state, root_uri, opts)

        {:reply, reply, state}

      {:error, reason} = error ->
        state = mark_degraded(state, root_uri, reason, opts)

        {:reply, error, state}
    end
  end

  def handle_call({:fetch_engine, root_uri}, _from, state) do
    {:reply, fetch_engine_handle(state, root_uri), state}
  end

  def handle_call({:status, root_uri}, _from, state) do
    status =
      case Map.fetch(state.degraded, root_uri) do
        {:ok, reason} ->
          EngineStatus.degraded(root_uri, reason, source_only?: source_only_mode(state, root_uri))

        :error ->
          case fetch_engine_handle(state, root_uri) do
            {:ok, engine} -> EngineStatus.running(engine)
            :error -> EngineStatus.missing(root_uri)
          end
      end

    {:reply, status, state}
  end

  def handle_call({:document_store, root_uri}, _from, state) do
    reply =
      case fetch_engine_handle(state, root_uri) do
        {:ok, engine} -> {:ok, engine.document_store}
        :error -> :error
      end

    {:reply, reply, state}
  end

  defp ensure_engine_started(state, root_uri, opts) do
    case fetch_engine_handle(state, root_uri) do
      {:ok, engine} ->
        {{:ok, engine}, clear_degraded(state, root_uri)}

      :error ->
        case backoff_reason(state, root_uri) do
          {:ok, reason} ->
            notify_status(
              opts,
              Status.project_degraded(root_uri, reason,
                source_only?: source_only_mode(state, root_uri)
              )
            )

            {{:error, {:backoff, reason}}, state}

          :error ->
            start_engine_with_state(state, root_uri, opts)
        end
    end
  end

  defp start_engine_with_state(state, root_uri, opts) do
    case start_engine(state.engine_supervisor, root_uri, opts) do
      {:ok, engine} ->
        state =
          state
          |> clear_degraded(root_uri)
          |> put_source_only(root_uri, source_only_mode(opts))

        {{:ok, engine}, state}

      {:error, reason} ->
        {{:error, reason}, mark_degraded(state, root_uri, reason, opts)}
    end
  end

  defp start_engine(engine_supervisor, root_uri, opts) do
    engine_opts =
      [root_uri: root_uri]
      |> Keyword.merge(engine_start_opts(opts))

    try do
      case DynamicSupervisor.start_child(engine_supervisor, {Engine, engine_opts}) do
        {:ok, pid} -> {:ok, Engine.handle(root_uri, pid, engine_opts)}
        {:error, {:already_started, pid}} -> {:ok, Engine.handle(root_uri, pid, engine_opts)}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  defp terminate_engine(state, root_uri) do
    case fetch_engine_handle(state, root_uri) do
      {:ok, engine} ->
        DynamicSupervisor.terminate_child(state.engine_supervisor, engine.pid)
        wait_until_unregistered(root_uri, state.unregister_timeout_ms)

      :error ->
        :ok
    end
  end

  defp wait_until_unregistered(root_uri, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    wait_until_unregistered(root_uri, deadline, timeout_ms)
  end

  defp wait_until_unregistered(root_uri, deadline, timeout_ms) do
    case Registry.lookup(@registry, {:engine, root_uri}) do
      [] ->
        :ok

      _still_registered ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :unregister_timeout}
        else
          Process.sleep(min(5, max(timeout_ms, 1)))
          wait_until_unregistered(root_uri, deadline, timeout_ms)
        end
    end
  end

  defp mark_degraded(state, root_uri, reason, opts) do
    Telemetry.execute([:project, :degraded], %{count: 1}, %{
      root_uri: root_uri,
      reason: reason
    })

    source_only? = source_only_mode(opts)

    notify_status(opts, Status.project_degraded(root_uri, reason, source_only?: source_only?))

    %{
      state
      | degraded: Map.put(state.degraded, root_uri, reason),
        backoff_until:
          Map.put(
            state.backoff_until,
            root_uri,
            System.monotonic_time(:millisecond) + state.restart_backoff_ms
          ),
        source_only: Map.put(state.source_only, root_uri, source_only?)
    }
  end

  defp clear_degraded(state, root_uri) do
    %{
      state
      | degraded: Map.delete(state.degraded, root_uri),
        backoff_until: Map.delete(state.backoff_until, root_uri)
    }
  end

  defp backoff_reason(state, root_uri) do
    with {:ok, deadline} <- Map.fetch(state.backoff_until, root_uri),
         true <- System.monotonic_time(:millisecond) < deadline,
         {:ok, reason} <- Map.fetch(state.degraded, root_uri) do
      {:ok, reason}
    else
      _not_in_backoff -> :error
    end
  end

  defp fetch_engine_handle(state, root_uri) do
    case Registry.lookup(@registry, {:engine, root_uri}) do
      [{pid, _value}] ->
        {:ok, Engine.handle(root_uri, pid, source_only?: source_only_mode(state, root_uri))}

      [] ->
        :error
    end
  end

  defp engine_start_opts(opts) do
    []
    |> maybe_put_status_target(opts)
    |> maybe_put_source_only(opts)
    |> maybe_put_project_indexing_enabled(opts)
    |> maybe_put_project_compilation_enabled(opts)
    |> maybe_put_compile_timeout(opts)
    |> maybe_put_compile_cache_root(opts)
    |> maybe_put_compile_command_runner(opts)
  end

  defp maybe_put_status_target(engine_opts, opts) do
    case Keyword.get(opts, :status_target) do
      pid when is_pid(pid) -> Keyword.put(engine_opts, :status_target, pid)
      _missing -> engine_opts
    end
  end

  defp maybe_put_project_indexing_enabled(engine_opts, opts) do
    case Keyword.fetch(opts, :project_indexing_enabled) do
      {:ok, enabled} when is_boolean(enabled) ->
        Keyword.put(engine_opts, :project_indexing_enabled, enabled)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp maybe_put_project_compilation_enabled(engine_opts, opts) do
    case Keyword.fetch(opts, :project_compilation_enabled) do
      {:ok, enabled} when is_boolean(enabled) ->
        Keyword.put(engine_opts, :project_compilation_enabled, enabled)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp maybe_put_source_only(engine_opts, opts) do
    case Keyword.fetch(opts, :source_only?) do
      {:ok, source_only?} when is_boolean(source_only?) ->
        Keyword.put(engine_opts, :source_only?, source_only?)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp maybe_put_compile_timeout(engine_opts, opts) do
    case Keyword.fetch(opts, :compile_timeout_ms) do
      {:ok, timeout_ms} when is_integer(timeout_ms) and timeout_ms > 0 ->
        Keyword.put(engine_opts, :compile_timeout_ms, timeout_ms)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp maybe_put_compile_cache_root(engine_opts, opts) do
    case Keyword.fetch(opts, :compile_cache_root) do
      {:ok, cache_root} when is_binary(cache_root) ->
        Keyword.put(engine_opts, :compile_cache_root, cache_root)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp maybe_put_compile_command_runner(engine_opts, opts) do
    case Keyword.fetch(opts, :compile_command_runner) do
      {:ok, command_runner} when is_function(command_runner, 3) ->
        Keyword.put(engine_opts, :compile_command_runner, command_runner)

      _missing_or_invalid ->
        engine_opts
    end
  end

  defp put_source_only(state, root_uri, source_only?) do
    %{state | source_only: Map.put(state.source_only, root_uri, source_only?)}
  end

  defp source_only_mode(opts) when is_list(opts), do: Keyword.get(opts, :source_only?, true)

  defp source_only_mode(state, root_uri) do
    Map.get(state.source_only, root_uri, true)
  end

  defp notify_status(opts, payload) do
    case Keyword.get(opts, :status_target) do
      pid when is_pid(pid) -> send(pid, {:phoenix_ls_status, payload})
      _missing -> :ok
    end
  end
end
