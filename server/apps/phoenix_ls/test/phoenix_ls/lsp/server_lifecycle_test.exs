defmodule PhoenixLS.LSP.ServerLifecycleTest do
  use ExUnit.Case, async: true

  import GenLSP.Test, only: [assert_result: 3]

  alias GenLSP.Enumerations.TextDocumentSyncKind
  alias GenLSP.LSP
  alias GenLSP.Notifications.Exit
  alias GenLSP.Requests.{Initialize, Shutdown}

  alias GenLSP.Structures.{
    ClientCapabilities,
    InitializeParams,
    InitializeResult,
    WorkspaceFolder
  }

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Project.{Manager, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  setup do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)

    lsp = %LSP{
      mod: Server,
      assigns: assigns,
      buffer: self(),
      pid: self(),
      task_supervisor: self(),
      tasks: %{},
      sync_notifications: MapSet.new()
    }

    %{lsp: lsp}
  end

  test "start_link reports missing GenLSP runtime options" do
    assert Server.start_link([]) ==
             {:error, {:missing_gen_lsp_options, [:buffer, :assigns, :task_supervisor]}}
  end

  test "init sets default lifecycle assigns", %{lsp: lsp} do
    assert {:ok, initialized_lsp} = Server.init(lsp, [])
    assert LSP.assigns(initialized_lsp).exit_code == 1
    assert LSP.assigns(initialized_lsp).root_uri == nil
    assert LSP.assigns(initialized_lsp).project_root_uri == nil
    assert LSP.assigns(initialized_lsp).document_store == DocumentStore
    assert LSP.assigns(initialized_lsp).project_manager == Manager
    assert LSP.assigns(initialized_lsp).workspace_folders == %{}
    assert LSP.assigns(initialized_lsp).workspace_project_roots == MapSet.new()
    assert is_function(LSP.assigns(initialized_lsp).exit_handler, 1)
  end

  test "initialize returns PhoenixLS server info and capabilities", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, [])

    params = %InitializeParams{
      process_id: nil,
      root_uri: "file:///tmp/example",
      capabilities: %ClientCapabilities{}
    }

    request = %Initialize{id: 1, params: params}

    assert {:reply, %InitializeResult{} = result, updated_lsp} =
             Server.handle_request(request, lsp)

    assert result.server_info.name == "PhoenixLS"
    assert result.server_info.version == PhoenixLS.version()
    assert result.capabilities.text_document_sync.open_close == true
    assert result.capabilities.text_document_sync.change == TextDocumentSyncKind.full()
    assert result.capabilities.completion_provider.trigger_characters == [".", ":"]
    assert result.capabilities.completion_provider.resolve_provider == true
    assert result.capabilities.hover_provider == true
    assert result.capabilities.definition_provider == true
    assert LSP.assigns(updated_lsp).root_uri == "file:///tmp/example"
    assert LSP.assigns(updated_lsp).project_root_uri == nil
    assert LSP.assigns(updated_lsp).document_store == DocumentStore
  end

  test "initialize tracks workspace folders and uses the first folder when root uri is nil",
       %{
         lsp: lsp
       } = context do
    first_root = fixture_project(context, "workspace_one")
    second_root = fixture_project(context, "workspace_two")
    first_uri = SupportURI.path_to_file_uri!(first_root)
    second_uri = SupportURI.path_to_file_uri!(second_root)

    {:ok, lsp} = Server.init(lsp, project_manager: Manager)

    params = %InitializeParams{
      process_id: nil,
      root_uri: nil,
      capabilities: %ClientCapabilities{},
      workspace_folders: [
        %WorkspaceFolder{uri: first_uri, name: "one"},
        %WorkspaceFolder{uri: second_uri, name: "two"}
      ]
    }

    assert {:reply, %InitializeResult{}, updated_lsp} =
             Server.handle_request(%Initialize{id: 1, params: params}, lsp)

    assert LSP.assigns(updated_lsp).root_uri == nil
    assert LSP.assigns(updated_lsp).project_root_uri == first_uri
    assert LSP.assigns(updated_lsp).document_store == Names.document_store(first_uri)

    assert LSP.assigns(updated_lsp).workspace_folders == %{
             first_uri => "one",
             second_uri => "two"
           }

    assert LSP.assigns(updated_lsp).workspace_project_roots ==
             MapSet.new([first_uri, second_uri])
  end

  test "initialize assigns the project engine document store for located Mix roots",
       %{
         lsp: lsp
       } = context do
    root_path = fixture_project(context, "server_project")
    nested_dir = Path.join(root_path, "lib")
    File.mkdir_p!(nested_dir)

    root_uri = SupportURI.path_to_file_uri!(root_path)
    nested_uri = SupportURI.path_to_file_uri!(nested_dir)

    {:ok, lsp} = Server.init(lsp, project_manager: Manager)

    params = %InitializeParams{
      process_id: nil,
      root_uri: nested_uri,
      capabilities: %ClientCapabilities{}
    }

    request = %Initialize{id: 1, params: params}

    assert {:reply, %InitializeResult{}, updated_lsp} = Server.handle_request(request, lsp)

    assert LSP.assigns(updated_lsp).root_uri == nested_uri
    assert LSP.assigns(updated_lsp).project_root_uri == root_uri
    assert LSP.assigns(updated_lsp).document_store == Names.document_store(root_uri)
  end

  test "initialize keeps fallback document store when no Mix project is found",
       %{
         lsp: lsp
       } = context do
    root_path = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root_path)

    {:ok, lsp} = Server.init(lsp, project_manager: Manager)

    params = %InitializeParams{
      process_id: nil,
      root_uri: root_uri,
      capabilities: %ClientCapabilities{}
    }

    request = %Initialize{id: 1, params: params}

    assert {:reply, %InitializeResult{}, updated_lsp} = Server.handle_request(request, lsp)

    assert LSP.assigns(updated_lsp).root_uri == root_uri
    assert LSP.assigns(updated_lsp).project_root_uri == nil
    assert LSP.assigns(updated_lsp).document_store == DocumentStore
  end

  test "shutdown marks the server ready to exit successfully", %{lsp: lsp} do
    {:ok, lsp} = Server.init(lsp, [])

    assert {:reply, nil, updated_lsp} = Server.handle_request(%Shutdown{id: 2}, lsp)
    assert LSP.assigns(updated_lsp).exit_code == 0
  end

  test "exit notification requests the default failure exit code", %{lsp: lsp} do
    parent = self()
    exit_handler = fn code -> send(parent, {:exit_requested, code}) end

    {:ok, lsp} = Server.init(lsp, exit_handler: exit_handler)

    assert {:noreply, ^lsp} = Server.handle_notification(%Exit{}, lsp)
    assert_receive {:exit_requested, 1}
  end

  test "exit notification requests success after shutdown", %{lsp: lsp} do
    parent = self()
    exit_handler = fn code -> send(parent, {:exit_requested, code}) end

    {:ok, lsp} = Server.init(lsp, exit_handler: exit_handler)
    {:reply, nil, lsp} = Server.handle_request(%Shutdown{id: 2}, lsp)

    assert {:noreply, ^lsp} = Server.handle_notification(%Exit{}, lsp)
    assert_receive {:exit_requested, 0}
  end

  test "unknown notifications are ignored", %{lsp: lsp} do
    assert {:noreply, ^lsp} = Server.handle_notification(:unknown_notification, lsp)
  end

  test "GenLSP lifecycle handles initialize, shutdown, and exit over transport" do
    parent = self()
    exit_handler = fn code -> send(parent, {:transport_exit_requested, code}) end

    test_server = GenLSP.Test.server(Server, init_args: [exit_handler: exit_handler])
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: "file:///tmp/example"
      }
    })

    version = PhoenixLS.version()
    full_sync = TextDocumentSyncKind.full()

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
            "change" => ^full_sync
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

    GenLSP.Test.request(test_client, %{id: 2, jsonrpc: "2.0", method: "shutdown"})
    assert_result(2, nil, 500)

    GenLSP.Test.notify(test_client, %{jsonrpc: "2.0", method: "exit", params: nil})

    assert_receive {:transport_exit_requested, 0}
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule ServerFixture.MixProject do
      use Mix.Project

      def project do
        [app: :server_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_server_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
