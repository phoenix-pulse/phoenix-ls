defmodule PhoenixLS.LSP.Capabilities do
  @moduledoc """
  Builds LSP server capabilities for the clean v2 server.

  Capabilities must not get ahead of implemented handlers. Add a capability
  only in the same change that handles the corresponding request or
  notification.
  """

  alias GenLSP.Enumerations.TextDocumentSyncKind

  alias GenLSP.Structures.{
    CompletionOptions,
    ServerCapabilities,
    SignatureHelpOptions,
    TextDocumentSyncOptions,
    WorkspaceFoldersServerCapabilities
  }

  def build do
    %ServerCapabilities{
      text_document_sync: %TextDocumentSyncOptions{
        open_close: true,
        change: TextDocumentSyncKind.full()
      },
      completion_provider: %CompletionOptions{
        trigger_characters: [".", ":"],
        resolve_provider: true
      },
      signature_help_provider: %SignatureHelpOptions{
        trigger_characters: ["<", " "],
        retrigger_characters: [" "]
      },
      hover_provider: true,
      definition_provider: true,
      workspace: %{
        workspace_folders: %WorkspaceFoldersServerCapabilities{
          supported: true,
          change_notifications: true
        }
      }
    }
  end
end
