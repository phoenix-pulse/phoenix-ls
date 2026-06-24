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
      |> LSP.assign(document_store: @store)

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

  defp open_notification do
    %TextDocumentDidOpen{
      params: %DidOpenTextDocumentParams{
        text_document: %TextDocumentItem{
          uri: @uri,
          language_id: "phoenix-heex",
          version: 1,
          text: "<div>Hello</div>"
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
end
