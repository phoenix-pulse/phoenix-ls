defmodule PhoenixLS.LSP.Server do
  @moduledoc """
  GenLSP lifecycle boundary for the PhoenixLS v2 language server.
  """

  use GenLSP

  alias PhoenixLS.LSP.Diagnostics
  alias PhoenixLS.LSP.Dispatcher
  alias PhoenixLS.LSP.ServerConfig
  alias PhoenixLS.LSP.Status
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
    server_config = Keyword.get(args, :server_config, ServerConfig.default())

    {:ok,
     assign(lsp,
       dispatcher: dispatcher,
       document_store: document_store,
       exit_code: 1,
       exit_handler: exit_handler,
       project_manager: project_manager,
       project_root_uri: nil,
       root_uri: nil,
       server_config: server_config,
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

  def handle_info({:phoenix_ls_status, payload}, lsp) do
    Status.publish(lsp, payload)
    refresh_project_diagnostics(lsp, payload)

    {:noreply, lsp}
  end

  defp refresh_project_diagnostics(
         lsp,
         %{
           "kind" => "indexing",
           "phase" => "completed",
           "job" => "project",
           "rootUri" => root_uri
         }
       )
       when is_binary(root_uri) do
    case Map.get(GenLSP.LSP.assigns(lsp), :project_manager) do
      nil ->
        :ok

      project_manager ->
        case Manager.fetch_engine(project_manager, root_uri) do
          {:ok, engine} ->
            Diagnostics.schedule_open_documents(lsp, engine.document_store, {:ok, engine})

          :error ->
            :ok
        end
    end
  end

  defp refresh_project_diagnostics(_lsp, _payload), do: :ok

  defp missing_gen_lsp_options(opts) do
    Enum.reject(@required_gen_lsp_options, &Keyword.has_key?(opts, &1))
  end

  defp dispatcher(lsp) do
    lsp
    |> GenLSP.LSP.assigns()
    |> Map.get(:dispatcher, Dispatcher)
  end
end
