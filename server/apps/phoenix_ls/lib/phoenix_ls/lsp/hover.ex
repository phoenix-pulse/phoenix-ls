defmodule PhoenixLS.LSP.Hover do
  @moduledoc """
  Handles LSP hover requests.
  """

  alias GenLSP.Requests.TextDocumentHover
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.Features.Policy
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
        config = RequestContext.server_config!(context)

        case reference_hover(uri, position, facts, config) do
          {:ok, hover} -> hover
          :not_found -> source_hover(uri, document.text, position, facts, config)
        end
      else
        _missing_or_invalid -> nil
      end

    {:reply, hover, context.lsp}
  end

  defp reference_hover(uri, position, facts, config) do
    if Policy.allow?(:hover, :navigation, config) do
      HoverFeature.reference_hover(uri, position, facts)
    else
      :not_found
    end
  end

  defp source_hover(uri, source, position, facts, config) do
    if Policy.allow?(:hover, :phoenix, config) do
      HoverFeature.hover_source(uri, source, position, facts)
    end
  end
end
