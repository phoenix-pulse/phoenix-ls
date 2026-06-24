defmodule PhoenixLS.LSP.Completion do
  @moduledoc """
  Handles LSP completion requests.
  """

  alias GenLSP.Requests.{CompletionItemResolve, TextDocumentCompletion}
  alias PhoenixLS.Features.Completion.{Components, Phoenix, Resolve}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentCompletion.t(), RequestContext.t()) :: {:reply, list(), GenLSP.LSP.t()}
  def handle(
        %TextDocumentCompletion{params: %{text_document: text_document, position: position}},
        %RequestContext{} = context
      ) do
    items =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, context} <- CursorContext.at(document.text, position) do
        facts = IndexStore.all(engine.index_store)

        Components.complete(context, facts) ++ Phoenix.complete(context, facts)
      else
        _missing_or_invalid -> []
      end

    {:reply, items, context.lsp}
  end

  @spec resolve(CompletionItemResolve.t(), RequestContext.t()) ::
          {:reply, GenLSP.Structures.CompletionItem.t(), GenLSP.LSP.t()}
  def resolve(%CompletionItemResolve{params: item}, %RequestContext{} = context) do
    {:reply, Resolve.resolve(item), context.lsp}
  end
end
