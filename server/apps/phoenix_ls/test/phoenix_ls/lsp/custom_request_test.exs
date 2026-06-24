defmodule PhoenixLS.LSP.CustomRequestTest do
  use ExUnit.Case, async: false

  alias GenLSP.LSP
  alias PhoenixLS.Index.{ElixirSource, Store}
  alias PhoenixLS.LSP.{CustomRequest, Dispatcher, Server}
  alias PhoenixLS.Project.Manager

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

  test "dispatcher handles phoenix explorer requests from the current project index", %{lsp: lsp} do
    root_uri = "file:///tmp/phoenix-ls-custom-request-#{System.unique_integer([:positive])}"
    {:ok, engine} = Manager.ensure_engine(Manager, root_uri)

    {:ok, facts} =
      ElixirSource.facts(root_uri <> "/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products/:id", ProductLive.Show, :show
        end
      end
      """)

    Enum.each(facts, &Store.put(engine.index_store, &1))

    lsp =
      LSP.assign(lsp,
        project_manager: Manager,
        project_root_uri: root_uri,
        workspace_project_roots: MapSet.new()
      )

    request = %CustomRequest{id: 8, method: "phoenix/listRoutes", params: %{}}

    assert {:reply,
            [
              %{
                "verb" => "live",
                "path" => "/products/:id",
                "liveModule" => "AppWeb.ProductLive.Show"
              }
            ], ^lsp} = Dispatcher.handle_request(request, lsp)
  end

  test "dispatcher returns an empty list when a phoenix explorer request has no project", %{
    lsp: lsp
  } do
    lsp =
      LSP.assign(lsp,
        project_manager: Manager,
        project_root_uri: nil,
        workspace_project_roots: MapSet.new()
      )

    request = %CustomRequest{id: 9, method: "phoenix/listSchemas", params: %{}}

    assert {:reply, [], ^lsp} = Dispatcher.handle_request(request, lsp)
  end
end
