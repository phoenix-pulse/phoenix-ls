defmodule PhoenixLS.LSP.ServerLifecycleTest do
  use ExUnit.Case, async: true

  alias GenLSP.LSP
  alias GenLSP.Requests.{Initialize, Shutdown}
  alias GenLSP.Structures.{ClientCapabilities, InitializeParams, InitializeResult}
  alias PhoenixLS.LSP.Server

  setup do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)

    lsp = %LSP{
      mod: Server,
      assigns: assigns,
      buffer: self(),
      pid: self(),
      task_supervisor: self(),
      tasks: %{},
      sync_notifications: MapSet.new()
    }

    %{lsp: lsp}
  end

  test "start_link reports missing GenLSP runtime options" do
    assert Server.start_link([]) ==
             {:error, {:missing_gen_lsp_options, [:buffer, :assigns, :task_supervisor]}}
  end

  test "init sets default lifecycle assigns", %{lsp: lsp} do
    assert {:ok, initialized_lsp} = Server.init(lsp, [])
    assert LSP.assigns(initialized_lsp).exit_code == 1
    assert LSP.assigns(initialized_lsp).root_uri == nil
  end

  test "initialize returns PhoenixLS server info and capabilities", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, [])

    params = %InitializeParams{
      process_id: nil,
      root_uri: "file:///tmp/example",
      capabilities: %ClientCapabilities{}
    }

    request = %Initialize{id: 1, params: params}

    assert {:reply, %InitializeResult{} = result, updated_lsp} =
             Server.handle_request(request, lsp)

    assert result.server_info.name == "PhoenixLS"
    assert result.server_info.version == PhoenixLS.version()
    assert result.capabilities.hover_provider == true
    assert LSP.assigns(updated_lsp).root_uri == "file:///tmp/example"
  end

  test "shutdown marks the server ready to exit successfully", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, [])

    assert {:reply, nil, updated_lsp} = Server.handle_request(%Shutdown{id: 2}, lsp)
    assert LSP.assigns(updated_lsp).exit_code == 0
  end

  test "unknown notifications are ignored", %{lsp: lsp} do
    assert {:noreply, ^lsp} = Server.handle_notification(:unknown_notification, lsp)
  end
end
