defmodule PhoenixLS.Workspace.DocumentStoreTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Workspace.DocumentStore

  test "opens, fetches, changes, and closes a document" do
    start_supervised!({DocumentStore, name: __MODULE__.Store})

    uri = "file:///tmp/page.html.heex"

    assert :ok = DocumentStore.open(__MODULE__.Store, uri, "heex", 1, "hello")
    assert {:ok, doc} = DocumentStore.fetch(__MODULE__.Store, uri)
    assert doc.uri == uri
    assert doc.language_id == "heex"
    assert doc.version == 1
    assert doc.text == "hello"

    assert :ok = DocumentStore.replace(__MODULE__.Store, uri, 2, "hello world")
    assert {:ok, updated} = DocumentStore.fetch(__MODULE__.Store, uri)
    assert updated.uri == uri
    assert updated.language_id == "heex"
    assert updated.version == 2
    assert updated.text == "hello world"

    assert :ok = DocumentStore.close(__MODULE__.Store, uri)
    assert :error = DocumentStore.fetch(__MODULE__.Store, uri)
  end

  test "returns not_found when replacing a missing document" do
    start_supervised!({DocumentStore, name: __MODULE__.MissingStore})

    assert {:error, :not_found} =
             DocumentStore.replace(
               __MODULE__.MissingStore,
               "file:///tmp/missing.ex",
               2,
               "missing"
             )
  end
end
