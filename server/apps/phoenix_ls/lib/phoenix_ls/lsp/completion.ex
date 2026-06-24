defmodule PhoenixLS.LSP.Completion do
  @moduledoc """
  Handles LSP completion requests.
  """

  alias GenLSP.LSP
  alias GenLSP.Requests.TextDocumentCompletion
  alias PhoenixLS.Features.Completion.Components
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentCompletion.t(), LSP.t()) :: {:reply, list(), LSP.t()}
  def handle(
        %TextDocumentCompletion{params: %{text_document: text_document, position: position}},
        lsp
      ) do
    items =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- project_engine(lsp, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri),
           {:ok, context} <- CursorContext.at(document.text, position) do
        facts = IndexStore.all(engine.index_store)

        Components.complete(context, facts)
      else
        _missing_or_invalid -> []
      end

    {:reply, items, lsp}
  end

  defp project_engine(lsp, uri) do
    assigns = LSP.assigns(lsp)

    with project_manager when not is_nil(project_manager) <- Map.get(assigns, :project_manager),
         root_uri when is_binary(root_uri) <- matching_project_root(assigns, uri) do
      case Manager.fetch_engine(project_manager, root_uri) do
        {:ok, engine} -> {:ok, engine}
        :error -> :error
      end
    else
      _missing -> :error
    end
  end

  defp matching_project_root(assigns, uri) do
    assigns
    |> known_project_roots()
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.find(&uri_within_root?(uri, &1))
  end

  defp known_project_roots(assigns) do
    workspace_roots =
      assigns
      |> Map.get(:workspace_project_roots, MapSet.new())
      |> MapSet.to_list()

    case Map.get(assigns, :project_root_uri) do
      nil -> workspace_roots
      root_uri -> [root_uri | workspace_roots]
    end
    |> Enum.uniq()
  end

  defp uri_within_root?(uri, root_uri) do
    uri == root_uri or String.starts_with?(uri, root_uri <> "/")
  end
end
