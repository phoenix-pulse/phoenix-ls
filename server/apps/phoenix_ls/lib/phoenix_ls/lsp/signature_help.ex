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
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri) do
        snapshot
        |> Snapshot.all()
        |> signature_help(document.text, position)
      else
        _missing_or_invalid -> nil
      end

    {:reply, result, context.lsp}
  end

  defp signature_help(facts, source, position) do
    SignatureHelpFeature.signature_help(source, position, facts) ||
      component_signature_help(source, position, facts)
  end

  defp component_signature_help(source, position, facts) do
    with {:ok, cursor_context} <- CursorContext.at(source, position) do
      SignatureHelpFeature.signature_help(cursor_context, facts)
    else
      _invalid_context -> nil
    end
  end
end
