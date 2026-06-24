defmodule PhoenixLS.LSP.TextDocumentSyncTest do
  use ExUnit.Case, async: true

  alias GenLSP.LSP

  alias GenLSP.Notifications.{
    TextDocumentDidChange,
    TextDocumentDidClose,
    TextDocumentDidOpen
  }

  alias GenLSP.Structures.{
    DidChangeTextDocumentParams,
    DidCloseTextDocumentParams,
    DidOpenTextDocumentParams,
    Position,
    Range,
    TextDocumentIdentifier,
    TextDocumentItem,
    VersionedTextDocumentIdentifier
  }

  alias PhoenixLS.LSP.{Server, TextDocumentSync}
  alias PhoenixLS.Project.{Manager, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  @store __MODULE__.DocumentStore
  @uri "file:///tmp/page.html.heex"

  setup do
    {:ok, assigns} = start_supervised(GenLSP.Assigns)
    start_supervised!({DocumentStore, name: @store})

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
      |> LSP.assign(document_store: @store, project_manager: Manager)

    %{lsp: lsp}
  end

  test "opens documents in the configured document store", %{lsp: lsp} do
    assert {:noreply, ^lsp} = TextDocumentSync.handle(open_notification(), lsp)

    assert {:ok, document} = DocumentStore.fetch(@store, @uri)
    assert document.uri == @uri
    assert document.language_id == "phoenix-heex"
    assert document.version == 1
    assert document.text == "<div>Hello</div>"
  end

  test "applies full document changes", %{lsp: lsp} do
    TextDocumentSync.handle(open_notification(), lsp)

    assert {:noreply, ^lsp} =
             TextDocumentSync.handle(
               change_notification(2, [%{text: "<div>Hello Phoenix</div>"}]),
               lsp
             )

    assert {:ok, document} = DocumentStore.fetch(@store, @uri)
    assert document.version == 2
    assert document.text == "<div>Hello Phoenix</div>"
  end

  test "ignores ranged document changes because incremental sync is not advertised", %{lsp: lsp} do
    TextDocumentSync.handle(open_notification(), lsp)

    ranged_change = %{
      range: %Range{
        start: %Position{line: 0, character: 5},
        end: %Position{line: 0, character: 10}
      },
      text: "Ignored"
    }

    assert {:noreply, ^lsp} =
             TextDocumentSync.handle(change_notification(2, [ranged_change]), lsp)

    assert {:ok, document} = DocumentStore.fetch(@store, @uri)
    assert document.version == 1
    assert document.text == "<div>Hello</div>"
  end

  test "uses the final full document change when a notification contains multiple changes", %{
    lsp: lsp
  } do
    TextDocumentSync.handle(open_notification(), lsp)

    assert {:noreply, ^lsp} =
             TextDocumentSync.handle(
               change_notification(2, [
                 %{text: "<div>Intermediate</div>"},
                 %{text: "<div>Final</div>"}
               ]),
               lsp
             )

    assert {:ok, document} = DocumentStore.fetch(@store, @uri)
    assert document.version == 2
    assert document.text == "<div>Final</div>"
  end

  test "closes documents in the configured document store", %{lsp: lsp} do
    TextDocumentSync.handle(open_notification(), lsp)
    assert {:ok, _document} = DocumentStore.fetch(@store, @uri)

    assert {:noreply, ^lsp} = TextDocumentSync.handle(close_notification(), lsp)

    assert DocumentStore.fetch(@store, @uri) == :error
  end

  test "routes opened documents to the store for the document URI project",
       %{
         lsp: lsp
       } = context do
    root = fixture_project(context, "document_project")
    document_uri = SupportURI.path_to_file_uri!(Path.join([root, "lib", "page.html.heex"]))
    project_store = Names.document_store(SupportURI.path_to_file_uri!(root))

    assert {:noreply, ^lsp} =
             TextDocumentSync.handle(
               open_notification(document_uri, "<div>Project</div>"),
               lsp
             )

    assert DocumentStore.fetch(@store, document_uri) == :error
    assert {:ok, document} = DocumentStore.fetch(project_store, document_uri)
    assert document.text == "<div>Project</div>"
  end

  defp open_notification do
    open_notification(@uri, "<div>Hello</div>")
  end

  defp open_notification(uri, text) do
    %TextDocumentDidOpen{
      params: %DidOpenTextDocumentParams{
        text_document: %TextDocumentItem{
          uri: uri,
          language_id: "phoenix-heex",
          version: 1,
          text: text
        }
      }
    }
  end

  defp change_notification(version, content_changes) do
    %TextDocumentDidChange{
      params: %DidChangeTextDocumentParams{
        text_document: %VersionedTextDocumentIdentifier{
          uri: @uri,
          version: version
        },
        content_changes: content_changes
      }
    }
  end

  defp close_notification do
    %TextDocumentDidClose{
      params: %DidCloseTextDocumentParams{
        text_document: %TextDocumentIdentifier{uri: @uri}
      }
    }
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule TextDocumentSyncFixture.MixProject do
      use Mix.Project

      def project do
        [app: :text_document_sync_fixture, version: "0.1.0", deps: []]
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
        "phoenix_ls_text_document_sync_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
