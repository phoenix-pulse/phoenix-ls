defmodule PhoenixLS.LSP.StatusTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_notification: 3, assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport publishes structured project indexing status", context do
    root = fixture_project(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{capabilities: %{}, processId: nil, rootUri: root_uri}
    })

    assert_result(1, %{"serverInfo" => %{"name" => "PhoenixLS"}}, 500)

    assert_notification(
      "phoenix/status",
      %{
        "kind" => "indexing",
        "phase" => "started",
        "job" => "project",
        "rootUri" => ^root_uri
      },
      500
    )

    assert_notification(
      "phoenix/status",
      %{
        "kind" => "indexing",
        "phase" => "completed",
        "job" => "project",
        "rootUri" => ^root_uri,
        "result" => "ok",
        "count" => 0
      },
      500
    )
  end

  defp fixture_project(context) do
    root =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_status_transport_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule StatusTransportFixture.MixProject do
      use Mix.Project

      def project do
        [app: :status_transport_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end
end
