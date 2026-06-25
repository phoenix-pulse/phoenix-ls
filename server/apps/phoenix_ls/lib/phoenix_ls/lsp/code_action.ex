defmodule PhoenixLS.LSP.CodeAction do
  @moduledoc """
  Handles LSP code action requests.
  """

  alias GenLSP.Requests.TextDocumentCodeAction
  alias PhoenixLS.Features.CodeAction, as: CodeActionFeature
  alias PhoenixLS.Index.Snapshot
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentCodeAction.t(), RequestContext.t()) ::
          {:reply, [GenLSP.Structures.CodeAction.t()], GenLSP.LSP.t()}
  def handle(
        %TextDocumentCodeAction{params: %{text_document: text_document, context: action_context}},
        %RequestContext{} = context
      ) do
    actions =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri) do
        CodeActionFeature.actions(
          document.text,
          uri,
          action_context.diagnostics,
          Snapshot.all(snapshot)
        )
      else
        _missing_or_invalid -> []
      end

    {:reply, actions, context.lsp}
  end
end
