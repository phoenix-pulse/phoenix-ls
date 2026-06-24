defmodule PhoenixLS.LSP.Capabilities do
  @moduledoc """
  Builds LSP server capabilities for the clean v2 server.

  Capabilities must not get ahead of implemented handlers. Add a capability
  only in the same change that handles the corresponding request or
  notification.
  """

  alias GenLSP.Enumerations.TextDocumentSyncKind
  alias GenLSP.Structures.{ServerCapabilities, TextDocumentSyncOptions}

  def build do
    %ServerCapabilities{
      text_document_sync: %TextDocumentSyncOptions{
        open_close: true,
        change: TextDocumentSyncKind.full()
      }
    }
  end
end
