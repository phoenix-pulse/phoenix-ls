defmodule PhoenixLS.LSP.WorkspaceFolders do
  @moduledoc """
  Tracks LSP workspace folders and located Mix project roots.
  """

  alias GenLSP.LSP
  alias GenLSP.Notifications.WorkspaceDidChangeWorkspaceFolders
  alias PhoenixLS.LSP.ServerConfig
  alias PhoenixLS.Project.Manager

  @type folder :: %{uri: String.t(), name: String.t()}

  @spec assign_initial(LSP.t(), list() | nil) :: LSP.t()
  def assign_initial(lsp, folders) do
    entries = folder_entries(folders)
    {folder_map, project_roots} = build_state(lsp, entries)

    LSP.assign(lsp,
      workspace_folders: folder_map,
      workspace_project_roots: project_roots
    )
  end

  @spec handle(WorkspaceDidChangeWorkspaceFolders.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(%WorkspaceDidChangeWorkspaceFolders{params: %{event: event}}, lsp) do
    added = folder_entries(event.added)
    removed = folder_entries(event.removed)
    assigns = LSP.assigns(lsp)

    folder_map =
      assigns.workspace_folders
      |> Map.drop(Enum.map(removed, & &1.uri))
      |> Map.merge(Map.new(added, &{&1.uri, &1.name}))

    project_roots =
      assigns.workspace_project_roots
      |> remove_project_roots(lsp, removed)
      |> add_project_roots(lsp, added)

    updated_lsp =
      LSP.assign(lsp,
        workspace_folders: folder_map,
        workspace_project_roots: project_roots
      )

    {:noreply, updated_lsp}
  end

  @spec first_uri(list() | nil) :: String.t() | nil
  def first_uri(nil), do: nil
  def first_uri([]), do: nil

  def first_uri([folder | _rest]) do
    folder
    |> folder_entry()
    |> case do
      %{uri: uri} -> uri
      nil -> nil
    end
  end

  defp build_state(lsp, entries) do
    folder_map = Map.new(entries, &{&1.uri, &1.name})
    project_roots = add_project_roots(MapSet.new(), lsp, entries)

    {folder_map, project_roots}
  end

  defp add_project_roots(project_roots, lsp, entries) do
    Enum.reduce(entries, project_roots, fn entry, roots ->
      case Manager.ensure_project_for_uri(
             project_manager(lsp),
             entry.uri,
             project_manager_opts(lsp)
           ) do
        {:ok, engine} -> MapSet.put(roots, engine.root_uri)
        _not_located -> roots
      end
    end)
  end

  defp remove_project_roots(project_roots, lsp, entries) do
    Enum.reduce(entries, project_roots, fn entry, roots ->
      case Manager.ensure_project_for_uri(
             project_manager(lsp),
             entry.uri,
             project_manager_opts(lsp)
           ) do
        {:ok, engine} -> MapSet.delete(roots, engine.root_uri)
        _not_located -> roots
      end
    end)
  end

  defp folder_entries(nil), do: []

  defp folder_entries(folders) when is_list(folders) do
    folders
    |> Enum.map(&folder_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp folder_entry(%{uri: uri, name: name}) when is_binary(uri) and is_binary(name) do
    %{uri: uri, name: name}
  end

  defp folder_entry(%{"uri" => uri, "name" => name}) when is_binary(uri) and is_binary(name) do
    %{uri: uri, name: name}
  end

  defp folder_entry(_folder), do: nil

  defp project_manager(lsp) do
    LSP.assigns(lsp).project_manager
  end

  defp project_manager_opts(lsp) do
    config = lsp |> LSP.assigns() |> Map.get(:server_config, ServerConfig.default())

    ServerConfig.project_manager_opts(config, lsp.pid)
  end
end
