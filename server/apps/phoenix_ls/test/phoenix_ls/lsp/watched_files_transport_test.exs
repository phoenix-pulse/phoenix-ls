defmodule PhoenixLS.LSP.WatchedFilesTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport routes watched file changes into the project index", context do
    root = fixture_project(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    path = Path.join([root, "lib", "transport_live.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule AppWeb.TransportLive do\nend\n")
    uri = SupportURI.path_to_file_uri!(path)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{capabilities: %{}, processId: nil, rootUri: root_uri}
    })

    assert_result(
      1,
      %{
        "capabilities" => %{
          "completionProvider" => %{"resolveProvider" => false, "triggerCharacters" => [".", ":"]},
          "experimental" => nil,
          "textDocumentSync" => %{"openClose" => true, "change" => 1},
          "workspace" => %{
            "workspaceFolders" => %{"supported" => true, "changeNotifications" => true}
          }
        },
        "serverInfo" => %{"name" => "PhoenixLS", "version" => "0.1.0"}
      },
      500
    )

    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "workspace/didChangeWatchedFiles",
      params: %{changes: [%{uri: uri, type: 2}]}
    })

    assert_eventually(fn ->
      assert ["AppWeb.TransportLive"] =
               Names.index_store(root_uri)
               |> IndexStore.all()
               |> Enum.map(& &1.id)
    end)
  end

  defp fixture_project(context) do
    root =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_watched_files_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule WatchedFilesFixture.MixProject do
      use Mix.Project

      def project do
        [app: :watched_files_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
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
