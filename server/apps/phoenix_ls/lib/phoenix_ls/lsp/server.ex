defmodule PhoenixLS.LSP.Server do
  @moduledoc """
  GenLSP lifecycle boundary for the PhoenixLS v2 language server.
  """

  use GenLSP

  alias PhoenixLS.LSP.Diagnostics
  alias PhoenixLS.LSP.Dispatcher
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
    dispatcher = Keyword.get(args, :dispatcher, Dispatcher)
    project_manager = Keyword.get(args, :project_manager, Manager)

    {:ok,
     assign(lsp,
       dispatcher: dispatcher,
       document_store: document_store,
       exit_code: 1,
       exit_handler: exit_handler,
       project_manager: project_manager,
       project_root_uri: nil,
       root_uri: nil,
       workspace_folders: %{},
       workspace_project_roots: MapSet.new()
     )}
  end

  @impl true
  def handle_request(request, lsp) do
    dispatcher(lsp).handle_request(request, lsp)
  end

  @impl true
  def handle_notification(notification, lsp) do
    dispatcher(lsp).handle_notification(notification, lsp)
  end

  @impl true
  def handle_info(
        {:phoenix_ls_publish_diagnostics, _uri, _token, _document_store, _project_engine} =
          message,
        lsp
      ) do
    Diagnostics.handle_info(message, lsp)
  end

  def handle_info(
        {:phoenix_ls_index_changed, _uri, _changed_kinds, _document_store, _project_engine} =
          message,
        lsp
      ) do
    Diagnostics.handle_info(message, lsp)
  end

  defp missing_gen_lsp_options(opts) do
    Enum.reject(@required_gen_lsp_options, &Keyword.has_key?(opts, &1))
  end

  defp dispatcher(lsp) do
    lsp
    |> GenLSP.LSP.assigns()
    |> Map.get(:dispatcher, Dispatcher)
  end
end
