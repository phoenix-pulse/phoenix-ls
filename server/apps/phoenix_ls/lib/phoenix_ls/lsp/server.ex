defmodule PhoenixLS.LSP.Server do
  @moduledoc """
  GenLSP lifecycle boundary for the PhoenixLS v2 language server.
  """

  use GenLSP

  alias GenLSP.Notifications.{
    Exit,
    TextDocumentDidChange,
    TextDocumentDidClose,
    TextDocumentDidOpen
  }

  alias GenLSP.Requests.{Initialize, Shutdown}
  alias GenLSP.Structures.{InitializeParams, InitializeResult}
  alias PhoenixLS.LSP.{Capabilities, TextDocumentSync}
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.DocumentStore

  @required_gen_lsp_options [:buffer, :assigns, :task_supervisor]

  def start_link(opts) when is_list(opts) do
    {init_args, gen_lsp_opts} = Keyword.pop(opts, :init_args, [])

    case missing_gen_lsp_options(gen_lsp_opts) do
      [] ->
        GenLSP.start_link(__MODULE__, init_args, gen_lsp_opts)

      missing ->
        {:error, {:missing_gen_lsp_options, missing}}
    end
  end

  @impl true
  def init(lsp, args) do
    exit_handler = Keyword.get(args, :exit_handler, &System.halt/1)
    document_store = Keyword.get(args, :document_store, DocumentStore)
    project_manager = Keyword.get(args, :project_manager, Manager)

    {:ok,
     assign(lsp,
       document_store: document_store,
       exit_code: 1,
       exit_handler: exit_handler,
       project_manager: project_manager,
       root_uri: nil
     )}
  end

  @impl true
  def handle_request(%Initialize{params: %InitializeParams{root_uri: root_uri}}, lsp) do
    lsp = assign_project(lsp, root_uri)

    result = %InitializeResult{
      capabilities: Capabilities.build(),
      server_info: %{name: "PhoenixLS", version: PhoenixLS.version()}
    }

    {:reply, result, assign(lsp, root_uri: root_uri)}
  end

  def handle_request(%Shutdown{}, lsp) do
    {:reply, nil, assign(lsp, exit_code: 0)}
  end

  @impl true
  def handle_notification(%Exit{}, lsp) do
    %{exit_code: exit_code, exit_handler: exit_handler} = GenLSP.LSP.assigns(lsp)

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

  def handle_notification(_notification, lsp) do
    {:noreply, lsp}
  end

  defp missing_gen_lsp_options(opts) do
    Enum.reject(@required_gen_lsp_options, &Keyword.has_key?(opts, &1))
  end

  defp assign_project(lsp, nil), do: lsp

  defp assign_project(lsp, root_uri) when is_binary(root_uri) do
    project_manager = GenLSP.LSP.assigns(lsp).project_manager

    case Manager.ensure_engine(project_manager, root_uri) do
      {:ok, engine} -> assign(lsp, document_store: engine.document_store)
      {:error, _reason} -> lsp
    end
  end
end
