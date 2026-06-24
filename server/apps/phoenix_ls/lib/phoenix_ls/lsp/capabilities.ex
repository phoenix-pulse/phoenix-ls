defmodule PhoenixLS.LSP.Capabilities do
  @moduledoc """
  Builds LSP server capabilities for the clean v2 server.
  """

  alias GenLSP.Enumerations.TextDocumentSyncKind

  alias GenLSP.Structures.{
    CompletionOptions,
    ServerCapabilities,
    TextDocumentSyncOptions
  }

  @trigger_characters ["<", " ", "-", ":", "\"", "=", "{", ".", "#", "@"]

  def build do
    %ServerCapabilities{
      text_document_sync: %TextDocumentSyncOptions{
        open_close: true,
        change: TextDocumentSyncKind.incremental()
      },
      completion_provider: %CompletionOptions{
        resolve_provider: true,
        trigger_characters: @trigger_characters
      },
      hover_provider: true,
      definition_provider: true
    }
  end
end
