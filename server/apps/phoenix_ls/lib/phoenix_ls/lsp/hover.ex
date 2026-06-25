defmodule PhoenixLS.LSP.Hover do
  @moduledoc """
  Handles LSP hover requests.
  """

  alias GenLSP.Requests.TextDocumentHover
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.Index.Snapshot
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
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri) do
        facts = Snapshot.all(snapshot)

        HoverFeature.hover_source(document.text, position, facts) ||
          HoverFeature.hover(uri, position, facts)
      else
        _missing_or_invalid -> nil
      end

    {:reply, hover, context.lsp}
  end
end
