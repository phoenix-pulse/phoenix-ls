defmodule PhoenixLS.Index.Indexer do
  @moduledoc """
  Background worker for project-scoped indexing jobs.
  """

  use GenServer

  alias PhoenixLS.Index.{DependencyGraph, DocumentIndexer, Invalidation, ProjectScan, Store}
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
    state = %{index_store: index_store}

    case Keyword.fetch(opts, :root_uri) do
      {:ok, root_uri} -> {:ok, state, {:continue, {:index_project, root_uri}}}
      :error -> {:ok, state}
    end
  end

  @impl true
  def handle_continue({:index_project, root_uri}, state) do
    emit_project_indexed(state.index_store, root_uri)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:index_document, document, opts}, state) do
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

    {:noreply, state}
  end

  def handle_cast({:index_uri, uri, opts}, state) do
    before_facts = Store.by_uri(state.index_store, uri)
    result = index_uri(state.index_store, uri)
    after_facts = Store.by_uri(state.index_store, uri)
    changed_kinds = DependencyGraph.changed_kinds(before_facts, after_facts)

    maybe_notify_index_changed(opts, uri, changed_kinds)

    Telemetry.execute([:indexer, :uri], %{count: fact_count(state.index_store, uri)}, %{
      uri: uri,
      result: result
    })

    {:noreply, state}
  end

  def handle_cast({:index_project, root_uri}, state) do
    emit_project_indexed(state.index_store, root_uri)

    {:noreply, state}
  end

  def handle_cast({:delete_uri, uri, opts}, state) do
    before_facts = Store.by_uri(state.index_store, uri)
    :ok = Invalidation.invalidate_uri(state.index_store, uri)
    after_facts = Store.by_uri(state.index_store, uri)
    changed_kinds = DependencyGraph.changed_kinds(before_facts, after_facts)

    maybe_notify_index_changed(opts, uri, changed_kinds)

    Telemetry.execute([:indexer, :delete], %{count: 1}, %{uri: uri, result: :ok})

    {:noreply, state}
  end

  defp index_uri(index_store, uri) do
    with {:ok, path} <- SupportURI.file_uri_to_path(uri),
         {:ok, language_id} <- language_id(path),
         {:ok, text} <- File.read(path) do
      document = Document.new(uri, language_id, 0, text)
      _result = DocumentIndexer.index(index_store, document)
      :ok
    else
      _ignored -> :ok
    end
  end

  defp emit_project_indexed(index_store, root_uri) do
    {result, count} = index_project(index_store, root_uri)

    Telemetry.execute([:indexer, :project], %{count: count}, %{
      root_uri: root_uri,
      result: result
    })
  end

  defp index_project(index_store, root_uri) do
    case ProjectScan.uris(root_uri) do
      {:ok, uris} ->
        Enum.each(uris, &index_uri(index_store, &1))

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

  defp language_id(path) do
    case Path.extname(path) do
      ".ex" -> {:ok, "elixir"}
      ".heex" -> {:ok, "phoenix-heex"}
      _other -> :error
    end
  end
end
