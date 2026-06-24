defmodule PhoenixLS.LSP.DiagnosticsTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_notification: 3, assert_result: 3]

  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  @fallback_store __MODULE__.DocumentStore

  test "GenLSP transport publishes Phoenix diagnostics after opening and changing HEEx documents",
       context do
    root = fixture_project(context, "diagnostics_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())

    assert_eventually(fn ->
      assert [_attr] = IndexStore.by_kind(Names.index_store(root_uri), :component_attr)
    end)

    open_document(test_client, heex_uri, "phoenix-heex", "<.button />")

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^heex_uri,
        "version" => 1,
        "diagnostics" => [
          %{
            "code" => "phoenix.missing_required_attr",
            "message" => "Missing required attr \"label\" for .button",
            "severity" => 1,
            "source" => "PhoenixLS"
          }
        ]
      },
      500
    )

    change_document(test_client, heex_uri, 2, ~s(<.button label="Save" />))

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^heex_uri,
        "version" => 2,
        "diagnostics" => []
      },
      500
    )
  end

  test "GenLSP transport refreshes open HEEx diagnostics after component dependency changes",
       context do
    root = fixture_project(context, "dependent_diagnostics_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())

    assert_eventually(fn ->
      assert [_attr] = IndexStore.by_kind(Names.index_store(root_uri), :component_attr)
    end)

    open_document(test_client, heex_uri, "phoenix-heex", "<.button />")

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^heex_uri,
        "version" => 1,
        "diagnostics" => [
          %{
            "code" => "phoenix.missing_required_attr",
            "message" => "Missing required attr \"label\" for .button",
            "severity" => 1,
            "source" => "PhoenixLS"
          }
        ]
      },
      500
    )

    change_document(test_client, component_uri, 2, component_source_without_required_attr())

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^heex_uri,
        "version" => 1,
        "diagnostics" => []
      },
      500
    )
  end

  test "GenLSP transport publishes and clears controller render template diagnostics",
       context do
    root = fixture_project(context, "template_diagnostics_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    controller_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/controllers/page_controller.ex"))

    template_uri =
      SupportURI.path_to_file_uri!(
        Path.join(root, "lib/app_web/controllers/page_html/index.html.heex")
      )

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, controller_uri, "elixir", controller_source())

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^controller_uri,
        "version" => 1,
        "diagnostics" => [
          %{
            "code" => "phoenix.unknown_template",
            "message" => "Unknown template \"index.html.heex\"",
            "severity" => 1,
            "source" => "PhoenixLS"
          }
        ]
      },
      500
    )

    open_document(test_client, template_uri, "phoenix-heex", "<h1>Index</h1>")

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^controller_uri,
        "version" => 1,
        "diagnostics" => []
      },
      500
    )
  end

  test "GenLSP transport clears diagnostics when HEEx documents close", context do
    root = fixture_project(context, "clear_diagnostics_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, heex_uri, "phoenix-heex", "<div />")

    assert_notification(
      "textDocument/publishDiagnostics",
      %{"uri" => ^heex_uri, "version" => 1, "diagnostics" => []},
      500
    )

    close_document(test_client, heex_uri)

    assert_notification(
      "textDocument/publishDiagnostics",
      %{"uri" => ^heex_uri, "diagnostics" => []},
      500
    )
  end

  test "GenLSP transport debounces rapid HEEx diagnostics changes", context do
    root = fixture_project(context, "debounced_diagnostics_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())

    assert_eventually(fn ->
      assert [_attr] = IndexStore.by_kind(Names.index_store(root_uri), :component_attr)
    end)

    open_document(test_client, heex_uri, "phoenix-heex", ~s(<.button label="Save" />))

    assert_notification(
      "textDocument/publishDiagnostics",
      %{"uri" => ^heex_uri, "version" => 1, "diagnostics" => []},
      500
    )

    change_document(test_client, heex_uri, 2, "<.button />")
    change_document(test_client, heex_uri, 3, ~s(<.button label="Save" />))

    refute_receive %{
                     "jsonrpc" => "2.0",
                     "method" => "textDocument/publishDiagnostics",
                     "params" => %{"uri" => ^heex_uri, "version" => 2}
                   },
                   25

    assert_notification(
      "textDocument/publishDiagnostics",
      %{"uri" => ^heex_uri, "version" => 3, "diagnostics" => []},
      500
    )
  end

  test "GenLSP transport publishes degraded diagnostics when no project engine is available" do
    start_supervised!({DocumentStore, name: @fallback_store})

    uri = "file:///tmp/phoenix_ls_no_project/page.html.heex"
    test_server = GenLSP.Test.server(Server, init_args: [document_store: @fallback_store])
    test_client = GenLSP.Test.client(test_server)

    open_document(test_client, uri, "phoenix-heex", "<.button />")

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => ^uri,
        "version" => 1,
        "diagnostics" => [
          %{
            "code" => "phoenix.project_unavailable",
            "message" => "Phoenix project engine is unavailable for this document",
            "severity" => 2,
            "source" => "PhoenixLS"
          }
        ]
      },
      500
    )
  end

  defp initialize(test_client, root_uri) do
    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: root_uri
      }
    })

    assert_result(1, %{"serverInfo" => %{"name" => "PhoenixLS"}}, 500)
  end

  defp open_document(test_client, uri, language_id, text) do
    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: %{
        textDocument: %{
          uri: uri,
          languageId: language_id,
          version: 1,
          text: text
        }
      }
    })
  end

  defp change_document(test_client, uri, version, text) do
    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didChange",
      params: %{
        textDocument: %{uri: uri, version: version},
        contentChanges: [%{text: text}]
      }
    })
  end

  defp close_document(test_client, uri) do
    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didClose",
      params: %{textDocument: %{uri: uri}}
    })
  end

  defp component_source do
    """
    defmodule AppWeb.CoreComponents do
      attr :label, :string, required: true

      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
      end
    end
    """
  end

  defp component_source_without_required_attr do
    """
    defmodule AppWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button>Save</button>
        \"\"\"
      end
    end
    """
  end

  defp controller_source do
    """
    defmodule AppWeb.PageController do
      def index(conn, _params) do
        render(conn, :index)
      end
    end
    """
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

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(Path.join(root, "lib/app_web/components"))
    File.mkdir_p!(Path.join(root, "lib/app_web/live"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule DiagnosticsFixture.MixProject do
      use Mix.Project

      def project do
        [app: :diagnostics_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_diagnostics_transport_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
