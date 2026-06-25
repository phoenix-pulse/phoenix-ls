defmodule PhoenixLS.LSP.DocumentSyncTransportTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Workspace.DocumentStore

  @store __MODULE__.DocumentStore
  @uri "file:///tmp/page.html.heex"

  test "GenLSP transport applies open, full change, and close notifications" do
    start_supervised!({DocumentStore, name: @store})

    test_server =
      GenLSP.Test.server(Server, init_args: [document_store: @store, project_manager: nil])

    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: %{
        textDocument: %{
          uri: @uri,
          languageId: "phoenix-heex",
          version: 1,
          text: "<div>Hello</div>"
        }
      }
    })

    assert_eventually(fn ->
      assert {:ok, document} = DocumentStore.fetch(@store, @uri)
      assert document.language_id == "phoenix-heex"
      assert document.version == 1
      assert document.text == "<div>Hello</div>"
    end)

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didChange",
      params: %{
        textDocument: %{uri: @uri, version: 2},
        contentChanges: [%{text: "<div>Hello Phoenix</div>"}]
      }
    })

    assert_eventually(fn ->
      assert {:ok, document} = DocumentStore.fetch(@store, @uri)
      assert document.version == 2
      assert document.text == "<div>Hello Phoenix</div>"
    end)

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didClose",
      params: %{textDocument: %{uri: @uri}}
    })

    assert_eventually(fn ->
      assert DocumentStore.fetch(@store, @uri) == :error
    end)
  end

  defp assert_eventually(fun, attempts_left \\ 20)

  defp assert_eventually(fun, attempts_left) do
    fun.()
  rescue
    exception in [ExUnit.AssertionError, MatchError] ->
      if attempts_left > 0 do
        Process.sleep(10)
        assert_eventually(fun, attempts_left - 1)
      else
        reraise exception, __STACKTRACE__
      end
  end
end
