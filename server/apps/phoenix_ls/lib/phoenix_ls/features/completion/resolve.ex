defmodule PhoenixLS.Features.Completion.Resolve do
  @moduledoc """
  Resolves additional completion item metadata carried in item data.
  """

  alias GenLSP.Structures.CompletionItem

  @spec resolve(CompletionItem.t()) :: CompletionItem.t()
  def resolve(%CompletionItem{} = item) do
    case documentation(item) do
      nil -> item
      documentation -> %{item | documentation: documentation}
    end
  end

  defp documentation(%CompletionItem{data: %{"documentation" => documentation}})
       when is_binary(documentation) do
    documentation
  end

  defp documentation(%CompletionItem{
         detail: detail,
         data: %{"kind" => "route_helper", "helper" => helper}
       })
       when is_binary(helper) do
    route_helper_documentation(detail || "Routes.#{helper}")
  end

  defp documentation(_item), do: nil

  defp route_helper_documentation(helper) do
    """
    #{helper}

    Phoenix route helper generated from indexed router routes. Prefer verified `~p` paths for new code when possible.
    """
    |> String.trim()
  end
end
