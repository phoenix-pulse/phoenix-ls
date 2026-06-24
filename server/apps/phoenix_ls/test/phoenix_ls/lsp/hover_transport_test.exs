defmodule PhoenixLS.LSP.HoverTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns component hover content from open project indexes", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "hover_project")
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
      method: "textDocument/hover",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 2,
                     "result" => %{
                       "contents" => %{
                         "kind" => "markdown",
                         "value" => value
                       }
                     }
                   },
                   500

    assert String.contains?(value, "component AppWeb.CoreComponents.button/1")
    assert String.contains?(value, "Renders a button.")
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
      500
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
      @doc "Renders a button."
      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
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
    defmodule HoverFixture.MixProject do
      use Mix.Project

      def project do
        [app: :hover_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)
    Path.join(System.tmp_dir!(), "phoenix_ls_hover_transport_#{name}")
  end
end
