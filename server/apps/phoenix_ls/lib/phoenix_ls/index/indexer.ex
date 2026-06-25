defmodule PhoenixLS.Index.Indexer do
  @moduledoc """
  Background worker for project-scoped indexing jobs.
  """

  use GenServer

  alias PhoenixLS.Index.{DependencyGraph, DocumentIndexer, Invalidation, ProjectScan, Store}
  alias PhoenixLS.Introspection.Asset
  alias PhoenixLS.LSP.Status
  alias PhoenixLS.Project.CompileRunner
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Support.Telemetry
  alias PhoenixLS.Workspace.Document

  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec schedule_document(server(), Document.t(), keyword()) :: :ok
  def schedule_document(server, %Document{} = document, opts \\ []) when is_list(opts) do
    GenServer.cast(server, {:index_document, document, opts})
  end

  @spec schedule_uri(server(), String.t(), keyword()) :: :ok
  def schedule_uri(server, uri, opts \\ []) when is_binary(uri) and is_list(opts) do
    GenServer.cast(server, {:index_uri, uri, opts})
  end

  @spec schedule_project(server(), String.t()) :: :ok
  def schedule_project(server, root_uri) when is_binary(root_uri) do
    GenServer.cast(server, {:index_project, root_uri})
  end

  @spec delete_uri(server(), String.t(), keyword()) :: :ok
  def delete_uri(server, uri, opts \\ []) when is_binary(uri) and is_list(opts) do
    GenServer.cast(server, {:delete_uri, uri, opts})
  end

  @impl true
  def init(opts) do
    index_store = Keyword.fetch!(opts, :index_store)

    state = %{
      index_store: index_store,
      root_uri: Keyword.get(opts, :root_uri),
      status_target: Keyword.get(opts, :status_target),
      project_indexing_enabled: Keyword.get(opts, :project_indexing_enabled, true),
      compile_runner: Keyword.get(opts, :compile_runner)
    }

    case Keyword.fetch(opts, :root_uri) do
      {:ok, root_uri} -> {:ok, state, {:continue, {:index_project, root_uri}}}
      :error -> {:ok, state}
    end
  end

  @impl true
  def handle_continue({:index_project, root_uri}, state) do
    maybe_compile_project(state, root_uri)
    notify_status(state, [], Status.indexing_started(root_uri: root_uri, job: :project))
    {result, count} = emit_project_indexed(state, root_uri)

    notify_status(
      state,
      [],
      Status.indexing_completed(root_uri: root_uri, job: :project, result: result, count: count)
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:index_document, document, opts}, state) do
    notify_status(
      state,
      opts,
      Status.indexing_started(
        root_uri: state.root_uri,
        uri: document.uri,
        job: :document
      )
    )

    before_facts = Store.by_uri(state.index_store, document.uri)
    result = DocumentIndexer.index(state.index_store, document)
    after_facts = Store.by_uri(state.index_store, document.uri)
    changed_kinds = DependencyGraph.changed_kinds(before_facts, after_facts)

    maybe_notify_index_changed(opts, document.uri, changed_kinds)

    Telemetry.execute(
      [:indexer, :document],
      %{count: fact_count(state.index_store, document.uri)},
      %{
        uri: document.uri,
        result: result
      }
    )

    notify_status(
      state,
      opts,
      Status.indexing_completed(
        root_uri: state.root_uri,
        uri: document.uri,
        job: :document,
        result: result,
        count: fact_count(state.index_store, document.uri)
      )
    )

    {:noreply, state}
  end

  def handle_cast({:index_uri, uri, opts}, state) do
    notify_status(
      state,
      opts,
      Status.indexing_started(root_uri: state.root_uri, uri: uri, job: :uri)
    )

    before_facts = Store.by_uri(state.index_store, uri)
    result = index_uri(state.index_store, uri, state.root_uri, state.project_indexing_enabled)
    after_facts = Store.by_uri(state.index_store, uri)
    changed_kinds = DependencyGraph.changed_kinds(before_facts, after_facts)

    maybe_notify_index_changed(opts, uri, changed_kinds)

    Telemetry.execute([:indexer, :uri], %{count: fact_count(state.index_store, uri)}, %{
      uri: uri,
      result: result
    })

    notify_status(
      state,
      opts,
      Status.indexing_completed(
        root_uri: state.root_uri,
        uri: uri,
        job: :uri,
        result: result,
        count: fact_count(state.index_store, uri)
      )
    )

    {:noreply, state}
  end

  def handle_cast({:index_project, root_uri}, state) do
    maybe_compile_project(state, root_uri)
    notify_status(state, [], Status.indexing_started(root_uri: root_uri, job: :project))
    {result, count} = emit_project_indexed(state, root_uri)

    notify_status(
      state,
      [],
      Status.indexing_completed(root_uri: root_uri, job: :project, result: result, count: count)
    )

    {:noreply, state}
  end

  def handle_cast({:delete_uri, uri, opts}, state) do
    notify_status(
      state,
      opts,
      Status.indexing_started(root_uri: state.root_uri, uri: uri, job: :delete)
    )

    before_facts = Store.by_uri(state.index_store, uri)
    :ok = Invalidation.invalidate_uri(state.index_store, uri)
    after_facts = Store.by_uri(state.index_store, uri)
    changed_kinds = DependencyGraph.changed_kinds(before_facts, after_facts)

    maybe_notify_index_changed(opts, uri, changed_kinds)

    Telemetry.execute([:indexer, :delete], %{count: 1}, %{uri: uri, result: :ok})

    notify_status(
      state,
      opts,
      Status.indexing_completed(
        root_uri: state.root_uri,
        uri: uri,
        job: :delete,
        result: :ok,
        count: 0
      )
    )

    {:noreply, state}
  end

  defp maybe_compile_project(%{compile_runner: nil}, _root_uri), do: :ok

  defp maybe_compile_project(%{compile_runner: compile_runner} = state, root_uri) do
    notify_status(state, [], Status.compilation_started(root_uri: root_uri))

    result =
      compile_runner
      |> CompileRunner.run(["compile", "--warnings-as-errors"])
      |> compile_result()

    notify_status(
      state,
      [],
      Status.compilation_completed(
        root_uri: root_uri,
        result: result,
        source_only?: compile_source_only?(result)
      )
    )

    maybe_notify_compile_degraded(state, root_uri, result)

    result
  end

  defp compile_result({:ok, %CompileRunner.Result{status: 0}}), do: :ok

  defp compile_result({:ok, %CompileRunner.Result{status: status}}),
    do: {:error, {:exit_status, status}}

  defp compile_result({:error, reason}), do: {:error, reason}

  defp compile_source_only?({:error, :source_only}), do: true
  defp compile_source_only?(_result), do: false

  defp maybe_notify_compile_degraded(_state, _root_uri, {:error, :source_only}), do: :ok
  defp maybe_notify_compile_degraded(_state, _root_uri, :ok), do: :ok

  defp maybe_notify_compile_degraded(state, root_uri, {:error, reason}) do
    notify_status(
      state,
      [],
      Status.project_degraded(root_uri, {:compile, reason}, source_only?: false)
    )
  end

  defp index_uri(_index_store, _uri, _root_uri, false), do: :disabled

  defp index_uri(index_store, uri, root_uri, true) do
    with {:ok, path} <- SupportURI.file_uri_to_path(uri),
         {:ok, index_target} <- index_target(path, root_uri) do
      index_path(index_store, uri, path, index_target)
    else
      _ignored -> :ok
    end
  end

  defp emit_project_indexed(%{project_indexing_enabled: false}, root_uri) do
    Telemetry.execute([:indexer, :project], %{count: 0}, %{
      root_uri: root_uri,
      result: :disabled
    })

    {:disabled, 0}
  end

  defp emit_project_indexed(%{index_store: index_store}, root_uri) do
    {result, count} = index_project(index_store, root_uri)

    Telemetry.execute([:indexer, :project], %{count: count}, %{
      root_uri: root_uri,
      result: result
    })

    {result, count}
  end

  defp index_project(index_store, root_uri) do
    case ProjectScan.uris(root_uri) do
      {:ok, uris} ->
        Enum.each(uris, &index_uri(index_store, &1, root_uri, true))

        {:ok, length(uris)}

      {:error, reason} ->
        {{:error, reason}, 0}
    end
  end

  defp fact_count(index_store, uri) do
    index_store
    |> PhoenixLS.Index.Store.by_uri(uri)
    |> length()
  end

  defp maybe_notify_index_changed(opts, uri, changed_kinds) do
    with true <- MapSet.size(changed_kinds) > 0,
         {pid, document_store, project_engine} <- Keyword.get(opts, :diagnostics),
         true <- is_pid(pid) do
      send(pid, {:phoenix_ls_index_changed, uri, changed_kinds, document_store, project_engine})
    else
      _ignored -> :ok
    end
  end

  defp notify_status(state, opts, payload) do
    case Keyword.get(opts, :status_target, state.status_target) do
      pid when is_pid(pid) -> send(pid, {:phoenix_ls_status, payload})
      _missing -> :ok
    end
  end

  defp index_target(path, root_uri) do
    case Path.extname(path) do
      ".ex" ->
        {:ok, {:document, "elixir"}}

      ".heex" ->
        {:ok, {:document, "phoenix-heex"}}

      _other ->
        asset_target(path, root_uri)
    end
  end

  defp asset_target(path, root_uri) when is_binary(root_uri) do
    with {:ok, root_path} <- SupportURI.file_uri_to_path(root_uri),
         true <- Asset.static_asset_path?(path, root_path) do
      {:ok, {:asset, root_path}}
    else
      _ignored -> :error
    end
  end

  defp asset_target(_path, _root_uri), do: :error

  defp index_path(index_store, uri, path, {:document, language_id}) do
    with {:ok, text} <- File.read(path) do
      document = Document.new(uri, language_id, 0, text)
      _result = DocumentIndexer.index(index_store, document)
      :ok
    else
      _ignored -> :ok
    end
  end

  defp index_path(index_store, uri, path, {:asset, root_path}) do
    :ok = Store.delete_uri(index_store, uri)

    uri
    |> Asset.facts(path, root_path)
    |> Enum.each(&Store.put(index_store, &1))

    :ok
  end
end
