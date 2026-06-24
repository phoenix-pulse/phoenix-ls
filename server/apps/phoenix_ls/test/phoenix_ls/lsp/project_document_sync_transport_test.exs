defmodule PhoenixLS.LSP.ProjectDocumentSyncTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 2]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Workspace.DocumentStore

  @root_uri "file:///tmp/phoenix-ls-project-document-sync"
  @document_uri "file:///tmp/phoenix-ls-project-document-sync/page.html.heex"

  test "GenLSP transport routes opened documents into the initialized project engine" do
    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: @root_uri
      }
    })

    assert_result(1, %{
      "capabilities" => %{
        "experimental" => nil,
        "textDocumentSync" => %{
          "openClose" => true,
          "change" => 1
        }
      },
      "serverInfo" => %{
        "name" => "PhoenixLS",
        "version" => "0.1.0"
      }
    })

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: %{
        textDocument: %{
          uri: @document_uri,
          languageId: "phoenix-heex",
          version: 1,
          text: "<div>Project</div>"
        }
      }
    })

    document_store = Names.document_store(@root_uri)

    assert_eventually(fn ->
      assert {:ok, document} = DocumentStore.fetch(document_store, @document_uri)
      assert document.version == 1
      assert document.text == "<div>Project</div>"
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
