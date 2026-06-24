defmodule PhoenixLS.Workspace.FileEvents do
  @moduledoc """
  Ingests editor and filesystem file-change events into project index jobs.
  """

  alias GenLSP.Enumerations.FileChangeType
  alias GenLSP.Structures.FileEvent
  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Support.URI, as: SupportURI

  @spec handle_lsp_events(GenServer.server(), [FileEvent.t()], keyword()) :: :ok
  def handle_lsp_events(project_manager, events, opts \\ [])

  def handle_lsp_events(nil, events, _opts) when is_list(events), do: :ok

  def handle_lsp_events(project_manager, events, opts) when is_list(events) and is_list(opts) do
    Enum.each(events, &handle_lsp_event(project_manager, &1, opts))

    :ok
  end

  @spec handle_file_system_event(GenServer.server(), String.t(), [atom()]) :: :ok
  def handle_file_system_event(project_manager, path, events)
      when is_binary(path) and is_list(events) do
    uri = SupportURI.path_to_file_uri!(path)
    type = file_system_change_type(events)

    handle_lsp_events(project_manager, [%FileEvent{uri: uri, type: type}])
  end

  defp handle_lsp_event(project_manager, %FileEvent{uri: uri, type: type}, opts) do
    case Manager.ensure_project_for_uri(project_manager, uri, manager_opts(opts)) do
      {:ok, engine} -> schedule(engine, uri, type, opts)
      _missing_or_unavailable -> :ok
    end
  end

  defp handle_lsp_event(_project_manager, _event, _opts), do: :ok

  defp schedule(engine, uri, type, opts) do
    indexer_opts = indexer_opts(engine, opts)

    cond do
      type == FileChangeType.deleted() ->
        Indexer.delete_uri(engine.indexer, uri, indexer_opts)

      type in [FileChangeType.created(), FileChangeType.changed()] ->
        Indexer.schedule_uri(engine.indexer, uri, indexer_opts)

      true ->
        :ok
    end
  end

  defp indexer_opts(engine, opts) do
    case Keyword.get(opts, :diagnostics_pid) do
      pid when is_pid(pid) ->
        [diagnostics: {pid, engine.document_store, {:ok, engine}}, status_target: pid]

      _other ->
        []
    end
  end

  defp manager_opts(opts) do
    case Keyword.get(opts, :diagnostics_pid) do
      pid when is_pid(pid) -> [status_target: pid]
      _missing -> []
    end
  end

  defp file_system_change_type(events) do
    cond do
      :deleted in events or :removed in events -> FileChangeType.deleted()
      :created in events -> FileChangeType.created()
      true -> FileChangeType.changed()
    end
  end
end
