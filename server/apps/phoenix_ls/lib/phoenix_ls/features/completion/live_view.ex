defmodule PhoenixLS.Features.Completion.LiveView do
  @moduledoc """
  Completion items for LiveView assigns and events.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: "@" <> assign_prefix}, facts) do
    facts
    |> facts_by_kind(:assign)
    |> Enum.map(&assign_item/1)
    |> prefixed_items("@" <> assign_prefix)
  end

  def complete(
        %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
        facts
      ) do
    facts
    |> facts_by_kind(:live_event)
    |> Enum.map(&event_item/1)
    |> prefixed_items(prefix)
  end

  def complete(_context, _facts), do: []

  defp assign_item(fact) do
    label = "@" <> fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.variable(),
       detail: "assign #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "assign", "id" => fact.id}
     }}
  end

  defp event_item(fact) do
    label = fact.data.event

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.event(),
       detail: "handle_event(\"#{label}\", ...)",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "live_event", "id" => fact.id}
     }}
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
