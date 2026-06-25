defmodule PhoenixLS.Features.Completion.LiveView do
  @moduledoc """
  Completion items for LiveView assigns and events.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.TemplateFacts
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
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

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    with uri when is_binary(uri) <- uri,
         {:ok, context} <- CursorContext.at(source, position),
         {:ok, module} <- TemplateFacts.module_for_uri(facts, uri) do
      complete_source_context(context, facts, module)
    else
      _not_scoped_context -> []
    end
  end

  defp complete_source_context(
         %CursorContext{kind: :expression, prefix: "@" <> prefix},
         facts,
         module
       ) do
    facts
    |> facts_by_kind(:assign)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.map(&assign_item/1)
    |> prefixed_items("@" <> prefix)
  end

  defp complete_source_context(
         %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
         facts,
         module
       ) do
    facts
    |> facts_by_kind(:live_event)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.map(&event_item/1)
    |> prefixed_items(prefix)
  end

  defp complete_source_context(_context, _facts, _module), do: []

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
