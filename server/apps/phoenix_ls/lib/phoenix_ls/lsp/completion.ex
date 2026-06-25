defmodule PhoenixLS.LSP.Completion do
  @moduledoc """
  Handles LSP completion requests.
  """

  alias GenLSP.Requests.{CompletionItemResolve, TextDocumentCompletion}
  alias PhoenixLS.Features.Completion.{Components, Phoenix, Resolve}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Snapshot
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
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, context} <- CursorContext.at(document.text, position) do
        facts = Snapshot.all(snapshot)

        Components.complete(document.text, position, facts) ++
          context_completion_items(context, facts) ++
          Phoenix.complete(uri, document.text, position, facts)
      else
        _missing_or_invalid -> []
      end

    {:reply, items, context.lsp}
  end

  @spec resolve(CompletionItemResolve.t(), RequestContext.t()) ::
          {:reply, GenLSP.Structures.CompletionItem.t(), GenLSP.LSP.t()}
  def resolve(%CompletionItemResolve{params: item}, %RequestContext{} = context) do
    {:reply, Resolve.resolve(item, known_project_facts(context)), context.lsp}
  end

  defp context_completion_items(
         %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event},
         _facts
       ),
       do: []

  defp context_completion_items(
         %CursorContext{kind: :expression, prefix: "@" <> prefix} = context,
         facts
       ) do
    if String.contains?(prefix, ".") do
      Phoenix.complete(context, facts)
    else
      []
    end
  end

  defp context_completion_items(%CursorContext{} = context, facts),
    do: Phoenix.complete(context, facts)

  defp known_project_facts(%RequestContext{} = context) do
    context
    |> RequestContext.known_project_roots()
    |> Enum.flat_map(fn root_uri ->
      case RequestContext.project_snapshot_for_uri(context, root_uri) do
        {:ok, snapshot} -> Snapshot.all(snapshot)
        :error -> []
      end
    end)
    |> Enum.uniq_by(&{&1.kind, &1.uri, &1.id})
  end
end
