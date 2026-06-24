defmodule PhoenixLS.Features.Completion.Phoenix do
  @moduledoc """
  Aggregates source-only Phoenix completion providers.
  """

  alias PhoenixLS.Features.Completion.{ElixirFallback, LiveView, Routes, Schemas, Snippets}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec complete(CursorContext.t(), [Fact.t()]) :: [GenLSP.Structures.CompletionItem.t()]
  def complete(%CursorContext{} = context, facts) when is_list(facts) do
    [
      Routes.complete(context, facts),
      Schemas.complete(context, facts),
      LiveView.complete(context, facts),
      Snippets.complete(context, facts),
      ElixirFallback.complete(context, facts)
    ]
    |> List.flatten()
    |> uniq_by_label()
  end

  defp uniq_by_label(items) do
    items
    |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
      if MapSet.member?(seen, item.label) do
        {seen, acc}
      else
        {MapSet.put(seen, item.label), [item | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
