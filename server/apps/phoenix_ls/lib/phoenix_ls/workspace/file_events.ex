defmodule PhoenixLS.Workspace.FileEvents do
  @moduledoc """
  Ingests editor and filesystem file-change events into project index jobs.
  """

  alias GenLSP.Enumerations.FileChangeType
  alias GenLSP.Structures.FileEvent
  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Support.URI, as: SupportURI

  @spec handle_lsp_events(GenServer.server(), [FileEvent.t()]) :: :ok
  def handle_lsp_events(nil, events) when is_list(events), do: :ok

  def handle_lsp_events(project_manager, events) when is_list(events) do
    Enum.each(events, &handle_lsp_event(project_manager, &1))

    :ok
  end

  @spec handle_file_system_event(GenServer.server(), String.t(), [atom()]) :: :ok
  def handle_file_system_event(project_manager, path, events)
      when is_binary(path) and is_list(events) do
    uri = SupportURI.path_to_file_uri!(path)
    type = file_system_change_type(events)

    handle_lsp_events(project_manager, [%FileEvent{uri: uri, type: type}])
  end

  defp handle_lsp_event(project_manager, %FileEvent{uri: uri, type: type}) do
    case Manager.ensure_project_for_uri(project_manager, uri) do
      {:ok, engine} -> schedule(engine, uri, type)
      _missing_or_unavailable -> :ok
    end
  end

  defp handle_lsp_event(_project_manager, _event), do: :ok

  defp schedule(engine, uri, type) do
    cond do
      type == FileChangeType.deleted() ->
        Indexer.delete_uri(engine.indexer, uri)

      type in [FileChangeType.created(), FileChangeType.changed()] ->
        Indexer.schedule_uri(engine.indexer, uri)

      true ->
        :ok
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
