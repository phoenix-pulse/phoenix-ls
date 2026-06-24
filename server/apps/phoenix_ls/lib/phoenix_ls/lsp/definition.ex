defmodule PhoenixLS.LSP.Definition do
  @moduledoc """
  Handles LSP definition requests.
  """

  alias GenLSP.Requests.TextDocumentDefinition
  alias PhoenixLS.Features.Definition, as: DefinitionFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Snapshot
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentDefinition.t(), RequestContext.t()) ::
          {:reply, GenLSP.Structures.Location.t() | nil, GenLSP.LSP.t()}
  def handle(
        %TextDocumentDefinition{params: %{text_document: text_document, position: position}},
        %RequestContext{} = context
      ) do
    definition =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, cursor_context} <- CursorContext.at(document.text, position) do
        facts = Snapshot.all(snapshot)

        DefinitionFeature.definition(cursor_context, facts) ||
          DefinitionFeature.definition(uri, position, facts)
      else
        _missing_or_invalid -> nil
      end

    {:reply, definition, context.lsp}
  end
end
