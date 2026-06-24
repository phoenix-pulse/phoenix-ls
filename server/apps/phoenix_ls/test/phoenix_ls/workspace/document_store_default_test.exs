defmodule PhoenixLS.Workspace.DocumentStoreDefaultTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Workspace.DocumentStore

  test "uses the supervised store by default" do
    uri = "file:///tmp/default-store-#{System.unique_integer([:positive])}.ex"

    on_exit(fn ->
      DocumentStore.close(uri)
    end)

    assert :ok = DocumentStore.open(uri, "elixir", 1, "default")
    assert {:ok, doc} = DocumentStore.fetch(uri)
    assert doc.text == "default"

    assert :ok = DocumentStore.close(uri)
    assert :error = DocumentStore.fetch(uri)
  end
end
