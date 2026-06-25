defmodule PhoenixLS.LSP.WorkspaceFoldersTest do
  use ExUnit.Case, async: true

  alias GenLSP.LSP

  alias GenLSP.Notifications.WorkspaceDidChangeWorkspaceFolders

  alias GenLSP.Structures.{
    DidChangeWorkspaceFoldersParams,
    WorkspaceFolder,
    WorkspaceFoldersChangeEvent
  }

  alias PhoenixLS.LSP.{Server, ServerConfig, WorkspaceFolders}
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Support.URI, as: SupportURI

  setup do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)

    lsp =
      %LSP{
        mod: Server,
        assigns: assigns,
        buffer: self(),
        pid: self(),
        task_supervisor: self(),
        tasks: %{},
        sync_notifications: MapSet.new()
      }
      |> LSP.assign(
        project_manager: PhoenixLS.Project.Manager,
        workspace_folders: %{},
        workspace_project_roots: MapSet.new()
      )

    %{lsp: lsp}
  end

  test "assign_initial tracks workspace folders and located project roots",
       %{
         lsp: lsp
       } = context do
    root = fixture_project(context, "initial")
    root_uri = SupportURI.path_to_file_uri!(root)

    updated_lsp =
      WorkspaceFolders.assign_initial(lsp, [%WorkspaceFolder{uri: root_uri, name: "initial"}])

    assert LSP.assigns(updated_lsp).workspace_folders == %{root_uri => "initial"}
    assert LSP.assigns(updated_lsp).workspace_project_roots == MapSet.new([root_uri])
  end

  test "assign_initial passes runtime config to located workspace projects",
       %{
         lsp: lsp
       } = context do
    root = fixture_project(context, "configured_initial")
    root_uri = SupportURI.path_to_file_uri!(root)

    lsp =
      LSP.assign(lsp,
        server_config: %ServerConfig{
          source_only?: true,
          project_indexing_enabled?: false,
          project_compilation_enabled?: false,
          log_level: :info
        }
      )

    updated_lsp =
      WorkspaceFolders.assign_initial(lsp, [
        %WorkspaceFolder{uri: root_uri, name: "configured_initial"}
      ])

    assert LSP.assigns(updated_lsp).workspace_project_roots == MapSet.new([root_uri])
    assert %{project_indexing_enabled: false} = :sys.get_state(Names.indexer(root_uri))
  end

  test "assign_initial keeps folders that are not Mix projects without project roots",
       %{
         lsp: lsp
       } = context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    updated_lsp =
      WorkspaceFolders.assign_initial(lsp, [%WorkspaceFolder{uri: root_uri, name: "plain"}])

    assert LSP.assigns(updated_lsp).workspace_folders == %{root_uri => "plain"}
    assert LSP.assigns(updated_lsp).workspace_project_roots == MapSet.new()
  end

  test "handle applies added and removed workspace folders", %{lsp: lsp} = context do
    removed_root = fixture_project(context, "removed")
    added_root = fixture_project(context, "added")
    removed_uri = SupportURI.path_to_file_uri!(removed_root)
    added_uri = SupportURI.path_to_file_uri!(added_root)

    lsp =
      WorkspaceFolders.assign_initial(lsp, [
        %WorkspaceFolder{uri: removed_uri, name: "removed"}
      ])

    notification = %WorkspaceDidChangeWorkspaceFolders{
      params: %DidChangeWorkspaceFoldersParams{
        event: %WorkspaceFoldersChangeEvent{
          added: [%WorkspaceFolder{uri: added_uri, name: "added"}],
          removed: [%WorkspaceFolder{uri: removed_uri, name: "removed"}]
        }
      }
    }

    assert {:noreply, updated_lsp} = WorkspaceFolders.handle(notification, lsp)

    assert LSP.assigns(updated_lsp).workspace_folders == %{added_uri => "added"}
    assert LSP.assigns(updated_lsp).workspace_project_roots == MapSet.new([added_uri])
  end

  test "first_uri returns the first workspace folder URI" do
    assert WorkspaceFolders.first_uri([
             %WorkspaceFolder{uri: "file:///tmp/one", name: "one"},
             %WorkspaceFolder{uri: "file:///tmp/two", name: "two"}
           ]) == "file:///tmp/one"

    assert WorkspaceFolders.first_uri(nil) == nil
    assert WorkspaceFolders.first_uri([]) == nil
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule WorkspaceFoldersFixture.MixProject do
      use Mix.Project

      def project do
        [app: :workspace_folders_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_workspace_folders_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
