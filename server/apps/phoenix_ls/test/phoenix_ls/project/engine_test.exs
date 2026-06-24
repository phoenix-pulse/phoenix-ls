defmodule PhoenixLS.Project.EngineTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Project.{Engine, Names}
  alias PhoenixLS.Workspace.DocumentStore

  @root_uri "file:///tmp/phoenix-ls-engine-test"
  @document_uri "file:///tmp/page.html.heex"

  setup_all do
    ensure_project_registry_started()
  end

  test "starts a named engine and project document store for the root uri" do
    assert {:ok, pid} = Engine.start_link(root_uri: @root_uri)
    assert is_pid(pid)

    document_store = Names.document_store(@root_uri)

    assert :ok =
             DocumentStore.open(
               document_store,
               @document_uri,
               "phoenix-heex",
               1,
               "hello"
             )

    assert {:ok, document} = DocumentStore.fetch(document_store, @document_uri)
    assert document.text == "hello"
  end

  test "builds a handle with the engine pid and document store" do
    pid = self()

    assert %Engine{
             root_uri: @root_uri,
             pid: ^pid,
             document_store: document_store
           } = Engine.handle(@root_uri, pid)

    assert document_store == Names.document_store(@root_uri)
  end

  defp ensure_project_registry_started do
    case Process.whereis(PhoenixLS.Project.Registry) do
      nil ->
        {:ok, pid} = Registry.start_link(keys: :unique, name: PhoenixLS.Project.Registry)

        on_exit(fn ->
          if Process.alive?(pid), do: Process.exit(pid, :normal)
        end)

      _pid ->
        :ok
    end
  end
end
