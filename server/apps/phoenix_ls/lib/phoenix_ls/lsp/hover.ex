defmodule PhoenixLS.LSP.Hover do
  @moduledoc """
  Handles LSP hover requests.
  """

  alias GenLSP.Requests.TextDocumentHover
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentHover.t(), RequestContext.t()) ::
          {:reply, GenLSP.Structures.Hover.t() | nil, GenLSP.LSP.t()}
  def handle(
        %TextDocumentHover{params: %{text_document: text_document, position: position}},
        %RequestContext{} = context
      ) do
    hover =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, cursor_context} <- CursorContext.at(document.text, position) do
        facts = IndexStore.all(engine.index_store)

        HoverFeature.hover(cursor_context, facts)
      else
        _missing_or_invalid -> nil
      end

    {:reply, hover, context.lsp}
  end
end
