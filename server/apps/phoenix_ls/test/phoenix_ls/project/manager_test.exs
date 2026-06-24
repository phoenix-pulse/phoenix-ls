defmodule PhoenixLS.Project.ManagerTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Project.{Engine, Manager}
  alias PhoenixLS.Workspace.DocumentStore

  @document_uri "file:///tmp/page.html.heex"

  setup_all do
    ensure_project_registry_started()
  end

  test "ensure_engine starts and reuses one engine per root uri" do
    %{manager: manager} = start_manager(__MODULE__.ReuseSupervisor, __MODULE__.ReuseManager)
    root_uri = "file:///tmp/phoenix-ls-manager-reuse"

    assert {:ok, %Engine{} = first} = Manager.ensure_engine(manager, root_uri)
    assert {:ok, %Engine{} = second} = Manager.ensure_engine(manager, root_uri)

    assert first.root_uri == root_uri
    assert first.pid == second.pid
    assert first.document_store == second.document_store
  end

  test "different root uris receive isolated document stores" do
    %{manager: manager} =
      start_manager(__MODULE__.IsolationSupervisor, __MODULE__.IsolationManager)

    assert {:ok, first} =
             Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-one")

    assert {:ok, second} =
             Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-two")

    refute first.pid == second.pid
    refute first.document_store == second.document_store

    assert :ok = DocumentStore.open(first.document_store, @document_uri, "phoenix-heex", 1, "one")

    assert :ok =
             DocumentStore.open(second.document_store, @document_uri, "phoenix-heex", 1, "two")

    assert {:ok, first_doc} = DocumentStore.fetch(first.document_store, @document_uri)
    assert {:ok, second_doc} = DocumentStore.fetch(second.document_store, @document_uri)
    assert first_doc.text == "one"
    assert second_doc.text == "two"
  end

  test "fetch_engine and document_store report missing roots without starting engines" do
    %{manager: manager} = start_manager(__MODULE__.MissingSupervisor, __MODULE__.MissingManager)

    assert Manager.fetch_engine(manager, "file:///tmp/missing") == :error
    assert Manager.document_store(manager, "file:///tmp/missing") == :error
  end

  defp start_manager(supervisor_name, manager_name) do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    %{manager: manager}
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
