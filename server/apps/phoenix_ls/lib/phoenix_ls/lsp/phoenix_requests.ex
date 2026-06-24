defmodule PhoenixLS.LSP.PhoenixRequests do
  @moduledoc """
  Handles Phoenix-specific editor explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests, as: Payloads
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.LSP.{CustomRequest, RequestContext}
  alias PhoenixLS.Project.Manager

  @known_methods MapSet.new([
                   "phoenix/listSchemas",
                   "phoenix/listComponents",
                   "phoenix/listRoutes",
                   "phoenix/listTemplates",
                   "phoenix/listEvents",
                   "phoenix/listLiveView"
                 ])

  @spec handle(CustomRequest.t(), RequestContext.t()) ::
          {:reply, list(map()) | nil, GenLSP.LSP.t()}
  def handle(%CustomRequest{method: method}, %RequestContext{} = context) do
    result =
      case project_facts(context) do
        {:ok, facts} -> Payloads.handle(method, facts)
        :error -> missing_project_result(method)
      end

    {:reply, result, context.lsp}
  end

  defp project_facts(%RequestContext{} = context) do
    with project_manager when not is_nil(project_manager) <-
           Map.get(context.assigns, :project_manager),
         root_uri when is_binary(root_uri) <-
           List.first(RequestContext.known_project_roots(context)),
         {:ok, engine} <- Manager.fetch_engine(project_manager, root_uri) do
      {:ok, IndexStore.all(engine.index_store)}
    else
      _missing -> :error
    end
  end

  defp missing_project_result(method) do
    if MapSet.member?(@known_methods, method), do: [], else: nil
  end
end
