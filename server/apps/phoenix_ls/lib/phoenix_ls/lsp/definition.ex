defmodule PhoenixLS.LSP.Definition do
  @moduledoc """
  Handles LSP definition requests.
  """

  alias GenLSP.Requests.TextDocumentDefinition
  alias PhoenixLS.Features.Definition, as: DefinitionFeature
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
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri) do
        facts = Snapshot.all(snapshot)

        case DefinitionFeature.reference_definition(uri, position, facts) do
          {:ok, definition} -> definition
          :not_found -> DefinitionFeature.definition_source(uri, document.text, position, facts)
        end
      else
        _missing_or_invalid -> nil
      end

    {:reply, definition, context.lsp}
  end
end
