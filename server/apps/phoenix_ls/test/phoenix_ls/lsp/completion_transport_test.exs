defmodule PhoenixLS.LSP.CompletionTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns component completions from open project indexes", context do
    root = fixture_project(context, "completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.bu| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      2,
      [
        %{
          "data" => %{"id" => "AppWeb.CoreComponents.button/1", "kind" => "component"},
          "detail" => "AppWeb.CoreComponents.button/1",
          "insertText" => ".button",
          "insertTextFormat" => 1,
          "kind" => 3,
          "label" => ".button"
        }
      ],
      500
    )
  end

  test "GenLSP transport returns an empty completion list for unsupported contexts", context do
    root = fixture_project(context, "empty_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<p>Hello |world</p>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(2, [], 500)
  end

  test "GenLSP transport returns route completions from indexed router facts", context do
    root = fixture_project(context, "route_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.link navigate={~p\"/prod|\"} />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      2,
      [
        %{
          "data" => %{
            "id" => "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show",
            "kind" => "route"
          },
          "detail" => "live AppWeb.ProductLive.Show :show",
          "insertText" => "/products/:id",
          "insertTextFormat" => 1,
          "kind" => 18,
          "label" => "/products/:id"
        }
      ],
      500
    )
  end

  test "GenLSP transport returns route helper completions in Elixir documents", context do
    root = fixture_project(context, "route_helper_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page_live.ex"))

    {elixir_source, position} = source_and_position("Routes.us|")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    open_document(test_client, elixir_uri, "elixir", elixir_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: elixir_uri},
        position: position
      }
    })

    assert_result(
      2,
      [
        %{
          "data" => %{"helper" => "user_path", "kind" => "route_helper"},
          "detail" => "Routes.user_path",
          "insertText" => "user_path(${1:conn_or_socket}, :${2|index,show|}, ${3:id})",
          "insertTextFormat" => 2,
          "kind" => 3,
          "label" => "user_path"
        },
        %{
          "data" => %{"helper" => "user_url", "kind" => "route_helper"},
          "detail" => "Routes.user_url",
          "insertText" => "user_url(${1:conn_or_socket}, :${2|index,show|}, ${3:id})",
          "insertTextFormat" => 2,
          "kind" => 3,
          "label" => "user_url"
        }
      ],
      500
    )
  end

  test "GenLSP transport resolves completion item documentation" do
    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 9,
      jsonrpc: "2.0",
      method: "completionItem/resolve",
      params: %{
        label: "label",
        detail: "attr :label, :string",
        data: %{
          "kind" => "component_attr",
          "id" => "AppWeb.CoreComponents.button/1:attr:label",
          "documentation" => "Visible label"
        }
      }
    })

    assert_result(
      9,
      %{
        "data" => %{
          "documentation" => "Visible label",
          "id" => "AppWeb.CoreComponents.button/1:attr:label",
          "kind" => "component_attr"
        },
        "detail" => "attr :label, :string",
        "documentation" => "Visible label",
        "label" => "label"
      },
      500
    )
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
          "experimental" => nil,
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
      attr :label, :string

      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
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
        live "/products/:id", ProductLive.Show, :show
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
    File.mkdir_p!(Path.join(root, "lib/app_web/components"))
    File.mkdir_p!(Path.join(root, "lib/app_web/live"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule CompletionFixture.MixProject do
      use Mix.Project

      def project do
        [app: :completion_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_completion_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
