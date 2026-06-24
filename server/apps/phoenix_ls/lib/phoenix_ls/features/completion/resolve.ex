defmodule PhoenixLS.Features.Completion.Resolve do
  @moduledoc """
  Resolves additional completion item metadata carried in item data.
  """

  alias GenLSP.Structures.CompletionItem

  @spec resolve(CompletionItem.t()) :: CompletionItem.t()
  def resolve(%CompletionItem{} = item) do
    case documentation(item.data) do
      nil -> item
      documentation -> %{item | documentation: documentation}
    end
  end

  defp documentation(%{"documentation" => documentation}) when is_binary(documentation) do
    documentation
  end

  defp documentation(_data), do: nil
end
