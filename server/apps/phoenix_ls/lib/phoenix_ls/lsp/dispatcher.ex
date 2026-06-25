defmodule PhoenixLS.LSP.Dispatcher do
  @moduledoc """
  Routes LSP requests and notifications to focused boundary modules.
  """

  alias GenLSP.LSP

  alias GenLSP.Notifications.{
    Exit,
    TextDocumentDidChange,
    TextDocumentDidClose,
    TextDocumentDidOpen,
    WorkspaceDidChangeWatchedFiles,
    WorkspaceDidChangeWorkspaceFolders
  }

  alias GenLSP.Requests.{
    CompletionItemResolve,
    Initialize,
    Shutdown,
    TextDocumentCompletion,
    TextDocumentDefinition,
    TextDocumentSignatureHelp,
    TextDocumentHover,
    WorkspaceExecuteCommand
  }

  alias GenLSP.Structures.{InitializeParams, InitializeResult}

  alias PhoenixLS.LSP.{
    Capabilities,
    Completion,
    CustomRequest,
    Definition,
    Hover,
    PhoenixRequests,
    RequestContext,
    SignatureHelp,
    TextDocumentSync,
    WorkspaceFolders
  }

  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.FileEvents

  @spec handle_request(term(), LSP.t()) :: {:reply, term(), LSP.t()} | {:noreply, LSP.t()}
  def handle_request(
        %Initialize{params: %InitializeParams{root_uri: root_uri, workspace_folders: folders}},
        lsp
      ) do
    lsp = WorkspaceFolders.assign_initial(lsp, folders)
    project_uri = root_uri || WorkspaceFolders.first_uri(folders)
    lsp = assign_project(lsp, project_uri)

    result = %InitializeResult{
      capabilities: Capabilities.build(),
      server_info: %{name: "PhoenixLS", version: PhoenixLS.version()}
    }

    {:reply, result, LSP.assign(lsp, root_uri: root_uri)}
  end

  def handle_request(%Shutdown{}, lsp) do
    {:reply, nil, LSP.assign(lsp, exit_code: 0)}
  end

  def handle_request(%TextDocumentCompletion{} = request, lsp) do
    Completion.handle(request, RequestContext.new(lsp))
  end

  def handle_request(%CompletionItemResolve{} = request, lsp) do
    Completion.resolve(request, RequestContext.new(lsp))
  end

  def handle_request(%TextDocumentHover{} = request, lsp) do
    Hover.handle(request, RequestContext.new(lsp))
  end

  def handle_request(%TextDocumentDefinition{} = request, lsp) do
    Definition.handle(request, RequestContext.new(lsp))
  end

  def handle_request(%TextDocumentSignatureHelp{} = request, lsp) do
    SignatureHelp.handle(request, RequestContext.new(lsp))
  end

  def handle_request(
        %WorkspaceExecuteCommand{
          id: id,
          params: %{command: "phoenix/" <> _suffix = method, arguments: arguments}
        },
        lsp
      ) do
    request = %CustomRequest{id: id, method: method, params: first_argument_map(arguments)}

    PhoenixRequests.handle(request, RequestContext.new(lsp))
  end

  def handle_request(%CustomRequest{} = request, lsp) do
    PhoenixRequests.handle(request, RequestContext.new(lsp))
  end

  @spec handle_notification(term(), LSP.t()) :: {:noreply, LSP.t()}
  def handle_notification(%Exit{}, lsp) do
    %{exit_code: exit_code, exit_handler: exit_handler} = LSP.assigns(lsp)

    exit_handler.(exit_code)

    {:noreply, lsp}
  end

  def handle_notification(%TextDocumentDidOpen{} = notification, lsp) do
    TextDocumentSync.handle(notification, lsp)
  end

  def handle_notification(%TextDocumentDidChange{} = notification, lsp) do
    TextDocumentSync.handle(notification, lsp)
  end

  def handle_notification(%TextDocumentDidClose{} = notification, lsp) do
    TextDocumentSync.handle(notification, lsp)
  end

  def handle_notification(%WorkspaceDidChangeWorkspaceFolders{} = notification, lsp) do
    WorkspaceFolders.handle(notification, lsp)
  end

  def handle_notification(%WorkspaceDidChangeWatchedFiles{params: %{changes: changes}}, lsp) do
    project_manager = LSP.assigns(lsp).project_manager
    :ok = FileEvents.handle_lsp_events(project_manager, changes, diagnostics_pid: lsp.pid)

    {:noreply, lsp}
  end

  def handle_notification(_notification, lsp) do
    {:noreply, lsp}
  end

  defp assign_project(lsp, nil), do: lsp

  defp assign_project(lsp, root_uri) when is_binary(root_uri) do
    project_manager = LSP.assigns(lsp).project_manager

    case Manager.ensure_project_for_uri(project_manager, root_uri, status_target: lsp.pid) do
      {:ok, engine} ->
        LSP.assign(lsp, document_store: engine.document_store, project_root_uri: engine.root_uri)

      :error ->
        lsp

      {:error, _reason} ->
        lsp
    end
  end

  defp first_argument_map([params | _rest]) when is_map(params), do: params
  defp first_argument_map(_arguments), do: %{}
end
