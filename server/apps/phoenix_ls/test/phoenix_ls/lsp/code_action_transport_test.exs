defmodule PhoenixLS.LSP.CodeActionTransportTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns missing required attr quick fixes", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root = fixture_project(context, "code_action_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    assert_indexed(component_uri, 4)
    open_document(test_client, heex_uri, "phoenix-heex", "<.button />")
    assert_indexed(heex_uri, 1)

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "method" => "textDocument/publishDiagnostics",
                     "params" => %{
                       "uri" => ^heex_uri,
                       "diagnostics" => [
                         %{
                           "code" => "phoenix.missing_required_attr",
                           "data" => %{
                             "kind" => "missing_required_attr",
                             "tag" => ".button",
                             "attr" => "label"
                           },
                           "range" => diagnostic_range
                         } = diagnostic
                       ]
                     }
                   },
                   500

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/codeAction",
      params: %{
        textDocument: %{uri: heex_uri},
        range: diagnostic_range,
        context: %{diagnostics: [diagnostic]}
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 2,
                     "result" => [
                       %{
                         "title" => "Add required attr \"label\"",
                         "kind" => "quickfix",
                         "edit" => %{
                           "changes" => %{
                             ^heex_uri => [
                               %{
                                 "newText" => " label=\"\"",
                                 "range" => %{
                                   "start" => %{"line" => 0, "character" => 8},
                                   "end" => %{"line" => 0, "character" => 8}
                                 }
                               }
                             ]
                           }
                         }
                       }
                     ]
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
    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{capabilities: %{}, processId: nil, rootUri: root_uri}
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

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule CodeActionFixture.MixProject do
      use Mix.Project

      def project do
        [app: :code_action_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_code_action_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
