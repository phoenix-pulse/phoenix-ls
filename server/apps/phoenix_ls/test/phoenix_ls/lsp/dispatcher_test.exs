defmodule PhoenixLS.LSP.DispatcherTest do
  use ExUnit.Case, async: false

  alias GenLSP.LSP
  alias GenLSP.Requests.Shutdown
  alias PhoenixLS.LSP.{Dispatcher, RequestContext, Server}
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.DocumentStore

  @store __MODULE__.DocumentStore

  defmodule FakeDispatcher do
    def handle_request({:fake_request, parent}, lsp) do
      send(parent, {:delegated_request, GenLSP.LSP.assigns(lsp).dispatcher})
      {:reply, :delegated, lsp}
    end

    def handle_notification({:fake_notification, parent}, lsp) do
      send(parent, {:delegated_notification, GenLSP.LSP.assigns(lsp).dispatcher})
      {:noreply, lsp}
    end
  end

  setup do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)
    start_supervised!({DocumentStore, name: @store})

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

  test "request context snapshots assigns and orders known project roots by longest prefix", %{
    lsp: lsp
  } do
    lsp =
      LSP.assign(lsp,
        project_manager: Manager,
        project_root_uri: "file:///workspace",
        workspace_project_roots: MapSet.new(["file:///workspace/apps/shop", "file:///other"])
      )

    context = RequestContext.new(lsp)

    assert context.lsp == lsp
    assert context.assigns.project_manager == Manager

    assert RequestContext.known_project_roots(context) == [
             "file:///workspace/apps/shop",
             "file:///workspace",
             "file:///other"
           ]
  end

  test "server delegates requests to the configured dispatcher", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, dispatcher: FakeDispatcher)

    assert Server.handle_request({:fake_request, self()}, lsp) == {:reply, :delegated, lsp}
    assert_receive {:delegated_request, FakeDispatcher}
  end

  test "server delegates notifications to the configured dispatcher", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, dispatcher: FakeDispatcher)

    assert Server.handle_notification({:fake_notification, self()}, lsp) == {:noreply, lsp}
    assert_receive {:delegated_notification, FakeDispatcher}
  end

  test "dispatcher handles shutdown through the request boundary", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, [])

    assert {:reply, nil, updated_lsp} = Dispatcher.handle_request(%Shutdown{id: 2}, lsp)
    assert LSP.assigns(updated_lsp).exit_code == 0
  end
end
