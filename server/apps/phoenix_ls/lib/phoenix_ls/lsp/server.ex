defmodule PhoenixLS.LSP.Server do
  @moduledoc """
  GenLSP lifecycle boundary for the PhoenixLS v2 language server.
  """

  use GenLSP

  alias GenLSP.Notifications.Exit
  alias GenLSP.Requests.{Initialize, Shutdown}
  alias GenLSP.Structures.{InitializeParams, InitializeResult}
  alias PhoenixLS.LSP.Capabilities

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

    {:ok, assign(lsp, exit_code: 1, exit_handler: exit_handler, root_uri: nil)}
  end

  @impl true
  def handle_request(%Initialize{params: %InitializeParams{root_uri: root_uri}}, lsp) do
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

  def handle_notification(_notification, lsp) do
    {:noreply, lsp}
  end

  defp missing_gen_lsp_options(opts) do
    Enum.reject(@required_gen_lsp_options, &Keyword.has_key?(opts, &1))
  end
end
