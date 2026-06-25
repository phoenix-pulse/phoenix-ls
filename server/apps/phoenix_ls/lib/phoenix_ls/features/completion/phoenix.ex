defmodule PhoenixLS.Features.Completion.Phoenix do
  @moduledoc """
  Aggregates source-only Phoenix completion providers.
  """

  alias PhoenixLS.Features.Completion.{
    Assets,
    ElixirFallback,
    LiveView,
    LiveViewJS,
    Routes,
    Schemas,
    Snippets
  }

  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [GenLSP.Structures.CompletionItem.t()]
  def complete(%CursorContext{} = context, facts) when is_list(facts) do
    [
      Routes.complete(context, facts),
      Assets.complete(context, facts),
      Schemas.complete(context, facts),
      LiveView.complete(context, facts),
      LiveViewJS.complete(context, facts),
      Snippets.complete(context, facts),
      ElixirFallback.complete(context, facts)
    ]
    |> List.flatten()
    |> uniq_by_label()
  end

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    source
    |> Routes.complete(position, facts)
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
