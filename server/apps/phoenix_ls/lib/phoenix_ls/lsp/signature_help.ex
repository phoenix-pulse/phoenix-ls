defmodule PhoenixLS.LSP.SignatureHelp do
  @moduledoc """
  Handles LSP signature help requests.
  """

  alias GenLSP.Requests.TextDocumentSignatureHelp
  alias PhoenixLS.Features.SignatureHelp, as: SignatureHelpFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Snapshot
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentSignatureHelp.t(), RequestContext.t()) ::
          {:reply, GenLSP.Structures.SignatureHelp.t() | nil, GenLSP.LSP.t()}
  def handle(
        %TextDocumentSignatureHelp{params: %{text_document: text_document, position: position}},
        %RequestContext{} = context
      ) do
    result =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, cursor_context} <- CursorContext.at(document.text, position) do
        snapshot
        |> Snapshot.all()
        |> then(&SignatureHelpFeature.signature_help(cursor_context, &1))
      else
        _missing_or_invalid -> nil
      end

    {:reply, result, context.lsp}
  end
end
