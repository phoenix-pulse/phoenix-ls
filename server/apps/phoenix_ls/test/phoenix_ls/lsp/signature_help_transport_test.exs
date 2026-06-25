defmodule PhoenixLS.LSP.SignatureHelpTransportTest do
  use ExUnit.Case, async: false

  import GenLSP.Test, only: [assert_result: 3]
  import PhoenixLS.Support.LSPConfigHelpers, only: [companion_config: 0]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns component signature help from open project indexes", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "signature_help_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.button la| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 5)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/signatureHelp",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 2,
                     "result" => %{
                       "activeParameter" => 0,
                       "activeSignature" => 0,
                       "signatures" => [
                         %{
                           "documentation" => %{
                             "kind" => "markdown",
                             "value" => documentation
                           },
                           "label" => "<.button label kind>",
                           "parameters" => [
                             %{
                               "documentation" => %{
                                 "kind" => "markdown",
                                 "value" => label_documentation
                               },
                               "label" => "label"
                             },
                             %{"label" => "kind"}
                           ]
                         }
                       ]
                     }
                   },
                   500

    assert String.contains?(documentation, "AppWeb.CoreComponents.button/1")
    assert String.contains?(label_documentation, "Required")
    assert String.contains?(label_documentation, "Visible label")
  end

  test "GenLSP transport keeps component signature help in companion mode", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "companion_signature_help_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.button la| />")

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 5)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 5,
      jsonrpc: "2.0",
      method: "textDocument/signatureHelp",
      params: %{textDocument: %{uri: heex_uri}, position: position}
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 5,
                     "result" => %{
                       "activeParameter" => 0,
                       "signatures" => [%{"label" => "<.button label kind>"}]
                     }
                   },
                   500
  end

  test "GenLSP transport omits ordinary Elixir signature help in companion mode", context do
    root = fixture_project(context, "companion_generic_signature_help_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app/example.ex"))

    {source, position} =
      source_and_position("""
      defmodule App.Example do
        def label(value), do: String.trim(|value)
      end
      """)

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, elixir_uri, "elixir", source)

    GenLSP.Test.request(test_client, %{
      id: 6,
      jsonrpc: "2.0",
      method: "textDocument/signatureHelp",
      params: %{textDocument: %{uri: elixir_uri}, position: position}
    })

    assert_result(6, nil, 500)
  end

  test "GenLSP transport does not return global slot signature help outside component scope",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "standalone_slot_signature_help_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<:item cl| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", slot_component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 5)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 4,
      jsonrpc: "2.0",
      method: "textDocument/signatureHelp",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 4,
                     "result" => nil
                   },
                   500
  end

  test "GenLSP transport returns route helper signature help from indexed router facts",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "route_signature_help_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))

    controller_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/controllers/user_controller.ex"))

    {controller_source, position} =
      source_and_position("""
      defmodule AppWeb.UserController do
        def show(conn, _params) do
          Routes.user_path(conn, :show, |id)
        end
      end
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    open_document(test_client, controller_uri, "elixir", controller_source)
    assert_indexed(router_uri, 3)
    assert_indexed(controller_uri, 3)

    GenLSP.Test.request(test_client, %{
      id: 3,
      jsonrpc: "2.0",
      method: "textDocument/signatureHelp",
      params: %{
        textDocument: %{uri: controller_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 3,
                     "result" => %{
                       "activeParameter" => 2,
                       "activeSignature" => 0,
                       "signatures" => [
                         %{
                           "documentation" => %{
                             "kind" => "markdown",
                             "value" => documentation
                           },
                           "label" => "Routes.user_path(conn_or_socket, action, id)",
                           "parameters" => [
                             %{"label" => "conn_or_socket"},
                             %{"label" => "action"},
                             %{"label" => "id"}
                           ]
                         }
                       ]
                     }
                   },
                   500

    assert String.contains?(documentation, "GET /users")
    assert String.contains?(documentation, "GET /users/:id")
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
            "triggerCharacters" => ["<", " ", "-", ":", "\"", "'", "=", "{", ".", "#", "@", "/"]
          },
          "definitionProvider" => true,
          "experimental" => nil,
          "hoverProvider" => true,
          "signatureHelpProvider" => %{
            "triggerCharacters" => ["<", " ", "(", ","],
            "retriggerCharacters" => [" ", ","]
          },
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
      attr :label, :string, required: true, doc: "Visible label"
      attr :kind, :atom, default: :primary

      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
      end
    end
    """
  end

  defp slot_component_source do
    """
    defmodule AppWeb.CoreComponents do
      slot :item do
        attr :class, :string
      end

      def button(assigns) do
        ~H\"\"\"
        <button><%= render_slot(@item) %></button>
        \"\"\"
      end
    end
    """
  end

  defp router_source do
    """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        get "/users", UserController, :index
        get "/users/:id", UserController, :show
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
    defmodule SignatureHelpFixture.MixProject do
      use Mix.Project

      def project do
        [app: :signature_help_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_signature_help_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
