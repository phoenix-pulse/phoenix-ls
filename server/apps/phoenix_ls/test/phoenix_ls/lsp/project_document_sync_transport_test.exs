defmodule PhoenixLS.LSP.ProjectDocumentSyncTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  test "GenLSP transport routes opened documents into the initialized project engine",
       context do
    root_path = fixture_project(context)
    nested_dir = Path.join(root_path, "lib")
    document_path = Path.join(nested_dir, "page.html.heex")

    root_uri = SupportURI.path_to_file_uri!(root_path)
    nested_uri = SupportURI.path_to_file_uri!(nested_dir)
    document_uri = SupportURI.path_to_file_uri!(document_path)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: nested_uri
      }
    })

    assert_result(
      1,
      %{
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
      },
      500
    )

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: %{
        textDocument: %{
          uri: document_uri,
          languageId: "phoenix-heex",
          version: 1,
          text: "<div>Project</div>"
        }
      }
    })

    document_store = Names.document_store(root_uri)

    assert_eventually(fn ->
      assert {:ok, document} = DocumentStore.fetch(document_store, document_uri)
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

  defp fixture_project(context) do
    root = Path.join(tmp_dir(context), "transport_project")
    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule TransportFixture.MixProject do
      use Mix.Project

      def project do
        [app: :transport_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)

    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_transport_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
