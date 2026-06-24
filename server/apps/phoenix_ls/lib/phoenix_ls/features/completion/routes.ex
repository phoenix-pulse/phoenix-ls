defmodule PhoenixLS.Features.Completion.Routes do
  @moduledoc """
  Completion items for verified `~p` route paths.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    case route_prefix(prefix) do
      {:ok, typed_path} ->
        facts
        |> facts_by_kind(:route)
        |> Enum.map(&route_item/1)
        |> prefixed_items(typed_path)

      :error ->
        []
    end
  end

  def complete(_context, _facts), do: []

  defp route_prefix("~p\"" <> path), do: {:ok, path}
  defp route_prefix("~p'" <> path), do: {:ok, path}
  defp route_prefix(_prefix), do: :error

  defp route_item(fact) do
    path = fact.data.path

    {path,
     %CompletionItem{
       label: path,
       kind: CompletionItemKind.reference(),
       detail: route_detail(fact),
       insert_text: path,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "route", "id" => fact.id}
     }}
  end

  defp route_detail(fact) do
    detail = "#{fact.data.verb} #{fact.data.plug}"

    case fact.data.action do
      nil -> detail
      action -> detail <> " :" <> Atom.to_string(action)
    end
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
