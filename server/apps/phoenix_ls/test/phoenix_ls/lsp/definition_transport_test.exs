defmodule PhoenixLS.LSP.DefinitionTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns component definition locations from open project indexes",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.button| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 3)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      2,
      %{
        "uri" => ^component_uri,
        "range" => %{
          "start" => %{"line" => 1, "character" => 2},
          "end" => %{"line" => 5, "character" => 5}
        }
      },
      500
    )
  end

  test "GenLSP transport returns template definition locations from controller render calls",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "template_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    controller_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/controllers/page_controller.ex"))

    template_uri =
      SupportURI.path_to_file_uri!(
        Path.join(root, "lib/app_web/controllers/page_html/index.html.heex")
      )

    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.PageController do
        def index(conn, _params) do
          render(conn, :in|dex)
        end
      end
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, controller_uri, "elixir", controller_source)
    open_document(test_client, template_uri, "phoenix-heex", "<h1>Index</h1>")
    assert_indexed(controller_uri, 3)
    assert_indexed(template_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{
        textDocument: %{uri: controller_uri},
        position: position
      }
    })

    assert_result(
      2,
      %{
        "uri" => ^template_uri,
        "range" => %{
          "start" => %{"line" => 0, "character" => 0},
          "end" => %{"line" => 0, "character" => 14}
        }
      },
      500
    )
  end

  test "GenLSP transport resolves HEEx event usages to same-module LiveView handlers",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "event_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    admin_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/admin/product_live.ex"))

    product_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.ex"))

    heex_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.html.heex"))

    {heex_source, position} = source_and_position(~s(<button phx-click="sa|ve">Save</button>))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, admin_uri, "elixir", live_view_source("AppWeb.Admin.ProductLive"))
    open_document(test_client, product_uri, "elixir", live_view_source("AppWeb.ProductLive"))
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(admin_uri, 4)
    assert_indexed(product_uri, 4)
    assert_indexed(heex_uri, 2)

    GenLSP.Test.request(test_client, %{
      id: 3,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 3,
                     "result" => %{"uri" => ^product_uri}
                   },
                   500
  end

  def handle_indexer_event(event, measurements, metadata, parent) do
    send(parent, {:indexer_event, event, measurements, metadata})
  end

  defp assert_indexed(uri, count) do
    assert_receive {:indexer_event, [:phoenix_ls, :indexer, :document], %{count: ^count},
                    %{uri: ^uri, result: :ok}},
                   500
  end

  defp initialize(test_client, root_uri) do
    version = PhoenixLS.version()

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

    assert_result(
      1,
      %{
        "capabilities" => %{
          "completionProvider" => %{
            "resolveProvider" => true,
            "triggerCharacters" => [".", ":"]
          },
          "definitionProvider" => true,
          "experimental" => nil,
          "hoverProvider" => true,
          "textDocumentSync" => %{
            "openClose" => true,
            "change" => 1
          },
          "workspace" => %{
            "workspaceFolders" => %{
              "supported" => true,
              "changeNotifications" => true
            }
          }
        },
        "serverInfo" => %{
          "name" => "PhoenixLS",
          "version" => ^version
        }
      },
      1_500
    )
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

  defp component_source do
    """
    defmodule AppWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
      end
    end
    """
  end

  defp live_view_source(module) do
    """
    defmodule #{module} do
      use Phoenix.LiveView

      def handle_event("save", _params, socket) do
        {:noreply, socket}
      end
    end
    """
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, %{line: position.line, character: position.character}}
  end

  defp marker_offset!(marked_source) do
    marked_source
    |> :binary.matches("|")
    |> case do
      [{offset, 1}] -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule DefinitionFixture.MixProject do
      use Mix.Project

      def project do
        [app: :definition_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)
    Path.join(System.tmp_dir!(), "phoenix_ls_definition_transport_#{name}")
  end
end
