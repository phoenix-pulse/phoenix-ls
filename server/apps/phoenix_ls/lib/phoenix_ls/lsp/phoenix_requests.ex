defmodule PhoenixLS.LSP.PhoenixRequests do
  @moduledoc """
  Handles Phoenix-specific editor explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests, as: Payloads
  alias PhoenixLS.LSP.{CustomRequest, RequestContext}

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
      case project_snapshot(context) do
        {:ok, snapshot} -> Payloads.handle(method, snapshot)
        :error -> missing_project_result(method)
      end

    {:reply, result, context.lsp}
  end

  defp project_snapshot(%RequestContext{} = context) do
    with root_uri when is_binary(root_uri) <-
           List.first(RequestContext.known_project_roots(context)),
         {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, root_uri) do
      {:ok, snapshot}
    else
      _missing -> :error
    end
  end

  defp missing_project_result(method) do
    if MapSet.member?(@known_methods, method), do: [], else: nil
  end
end
