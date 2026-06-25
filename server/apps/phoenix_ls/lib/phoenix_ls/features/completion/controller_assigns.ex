defmodule PhoenixLS.Features.Completion.ControllerAssigns do
  @moduledoc """
  Controller-rendered template assign completions.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.ControllerTemplate
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec complete(String.t() | nil, CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(uri, %CursorContext{kind: :expression, prefix: "@" <> prefix}, facts)
      when (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    with uri when is_binary(uri) <- uri do
      facts
      |> ControllerTemplate.assign_facts(uri)
      |> Enum.map(&assign_item/1)
      |> prefixed_items("@" <> prefix)
      |> uniq_by_label()
    else
      _not_controller_template -> []
    end
  end

  def complete(_uri, _context, _facts), do: []

  defp assign_item(%Fact{kind: :controller_assign} = fact) do
    label = "@" <> fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.variable(),
       detail: "controller assign #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "controller_assign", "id" => fact.id}
     }}
  end

  defp assign_item(%Fact{kind: :controller_plug_assign} = fact) do
    label = "@" <> fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.variable(),
       detail: "controller plug assign #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "controller_plug_assign", "id" => fact.id}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
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
