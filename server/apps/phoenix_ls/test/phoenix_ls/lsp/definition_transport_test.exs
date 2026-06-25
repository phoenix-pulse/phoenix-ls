defmodule PhoenixLS.LSP.DefinitionTransportTest do
  use ExUnit.Case, async: false

  import GenLSP.Test, only: [assert_result: 3]
  import PhoenixLS.Support.LSPConfigHelpers, only: [companion_config: 0]

  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.Names
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
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 3)
    assert_indexed(page_uri, 2)
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

  test "GenLSP transport keeps component definition locations in companion mode", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "companion_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.button| />")

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri, 3)
    assert_indexed(page_uri, 2)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 6,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{textDocument: %{uri: heex_uri}, position: position}
    })

    assert_result(6, %{"uri" => ^component_uri}, 500)
  end

  test "GenLSP transport resolves definitions after single-file project discovery",
       context do
    root = fixture_project(context, "single_file_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_path = Path.join(root, "lib/app_web/components/core_components.ex")
    component_uri = SupportURI.path_to_file_uri!(component_path)
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    File.mkdir_p!(Path.dirname(component_path))
    File.write!(component_path, component_source())
    write_page_module!(root)

    {heex_source, position} = source_and_position("<.button| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize_without_root(test_client)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    assert_eventually(fn ->
      assert [_component] = IndexStore.by_kind(Names.index_store(root_uri), :component)
    end)

    GenLSP.Test.request(test_client, %{
      id: 8,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{textDocument: %{uri: heex_uri}, position: position}
    })

    assert_result(8, %{"uri" => ^component_uri}, 500)
  end

  test "GenLSP transport omits ordinary Elixir definition in companion mode", context do
    root = fixture_project(context, "companion_generic_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app/example.ex"))

    {source, position} =
      source_and_position("""
      defmodule App.Example do
        def label(value), do: to_str|ing(value)
      end
      """)

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, elixir_uri, "elixir", source)

    GenLSP.Test.request(test_client, %{
      id: 7,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{textDocument: %{uri: elixir_uri}, position: position}
    })

    assert_result(7, nil, 500)
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

  test "GenLSP transport resolves HEEx schema field access to schema sources", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "schema_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    schema_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app/catalog/product.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<p>{@product.na|me}</p>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, schema_uri, "elixir", schema_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(schema_uri, 3)

    GenLSP.Test.request(test_client, %{
      id: 5,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 5,
                     "result" => %{"uri" => ^schema_uri}
                   },
                   500
  end

  test "GenLSP transport resolves HEEx assigns to same-module LiveView assign sources",
       context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "assign_definition_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    admin_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/admin/product_live.ex"))

    product_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.ex"))

    heex_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.html.heex"))

    {heex_source, position} = source_and_position("<p>{@selected|_id}</p>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)

    open_document(
      test_client,
      admin_uri,
      "elixir",
      live_view_assign_source("AppWeb.Admin.ProductLive")
    )

    open_document(
      test_client,
      product_uri,
      "elixir",
      live_view_assign_source("AppWeb.ProductLive")
    )

    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(admin_uri, 5)
    assert_indexed(product_uri, 5)
    assert_indexed(heex_uri, 1)

    GenLSP.Test.request(test_client, %{
      id: 4,
      jsonrpc: "2.0",
      method: "textDocument/definition",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 4,
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
            "triggerCharacters" => ["<", " ", "-", ":", "\"", "'", "=", "{", ".", "#", "@", "/"]
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

  defp initialize_without_root(test_client) do
    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: nil,
        workspaceFolders: nil
      }
    })

    assert_result(1, %{"serverInfo" => %{"name" => "PhoenixLS"}}, 1_500)
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

  defp open_page_module(test_client, root) do
    page_uri = SupportURI.path_to_file_uri!(write_page_module!(root))

    open_document(test_client, page_uri, "elixir", page_module_source())

    page_uri
  end

  defp write_page_module!(root) do
    path = Path.join(root, "lib/app_web/live/page.ex")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, page_module_source())
    path
  end

  defp page_module_source do
    """
    defmodule AppWeb.Page do
      import AppWeb.CoreComponents
    end
    """
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

  defp schema_source do
    """
    defmodule App.Catalog.Product do
      use Ecto.Schema

      schema "products" do
        field :name, :string
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

  defp live_view_assign_source(module) do
    """
    defmodule #{module} do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :selected_id, "1")}
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

  defp assert_eventually(fun, attempts_left \\ 20)

  defp assert_eventually(fun, attempts_left) do
    fun.()
  rescue
    exception in [ExUnit.AssertionError, MatchError] ->
      if attempts_left > 0 do
        Process.sleep(25)
        assert_eventually(fun, attempts_left - 1)
      else
        reraise exception, __STACKTRACE__
      end
  catch
    :exit, reason ->
      if attempts_left > 0 do
        Process.sleep(25)
        assert_eventually(fun, attempts_left - 1)
      else
        exit(reason)
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
