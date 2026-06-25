defmodule PhoenixLS.LSP.RequestContextTest do
  use ExUnit.Case, async: false

  alias GenLSP.LSP
  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{Fact, Snapshot, Store}
  alias PhoenixLS.LSP.{RequestContext, Server, ServerConfig}
  alias PhoenixLS.Project.{Manager, Names}
  alias PhoenixLS.Support.URI, as: SupportURI

  setup context do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)

    supervisor_name =
      Module.concat(__MODULE__, :"Supervisor#{System.unique_integer([:positive])}")

    manager_name = Module.concat(__MODULE__, :"Manager#{System.unique_integer([:positive])}")

    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    {:ok, engine} = Manager.ensure_engine(manager, root_uri)

    lsp =
      %LSP{
        mod: Server,
        assigns: assigns,
        buffer: self(),
        pid: self(),
        task_supervisor: self(),
        tasks: %{},
        sync_notifications: MapSet.new()
      }
      |> LSP.assign(project_manager: manager, project_root_uri: root_uri)

    %{context: RequestContext.new(lsp), engine: engine, root_uri: root_uri}
  end

  test "returns a snapshot for a document in a known project", %{
    context: context,
    engine: engine,
    root_uri: root_uri
  } do
    fact = fact(:component, "AppWeb.CoreComponents.button/1")
    Store.put(engine.index_store, fact)

    uri = root_uri <> "/lib/app_web/live/page.html.heex"

    assert {:ok, snapshot} = RequestContext.project_snapshot_for_uri(context, uri)
    assert Snapshot.by_kind(snapshot, :component) == [fact]
  end

  test "project snapshots stay immutable after index store changes", %{
    context: context,
    engine: engine,
    root_uri: root_uri
  } do
    first = fact(:component, "AppWeb.CoreComponents.button/1")
    second = fact(:route, "AppWeb.Router:live:/products:AppWeb.ProductLive.Index:index")
    Store.put(engine.index_store, first)

    uri = root_uri <> "/lib/app_web/live/page.html.heex"

    assert {:ok, snapshot} = RequestContext.project_snapshot_for_uri(context, uri)

    Store.put(engine.index_store, second)

    assert Snapshot.all(snapshot) == [first]
    assert Snapshot.by_kind(snapshot, :route) == []
    assert Store.by_kind(Names.index_store(root_uri), :route) == [second]
  end

  test "returns error when uri is outside known projects", %{context: context} do
    assert RequestContext.project_snapshot_for_uri(
             context,
             "file:///tmp/elsewhere/page.html.heex"
           ) ==
             :error
  end

  test "fetches server config from initialized assigns", %{
    context: %RequestContext{} = context
  } do
    config = ServerConfig.default()
    context = %RequestContext{context | assigns: Map.put(context.assigns, :server_config, config)}

    assert RequestContext.server_config!(context) == config
  end

  test "raises when server config is missing", %{context: context} do
    assert_raise KeyError, fn ->
      RequestContext.server_config!(context)
    end
  end

  defp fact(kind, id) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: "file:///tmp/app/lib/app_web/source.ex",
      range: %Range{
        start: %Position{line: 0, character: 0},
        end: %Position{line: 0, character: 1}
      },
      provenance: %{source: :request_context_test},
      data: %{name: id}
    )
  end

  defp tmp_dir(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_request_context_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
