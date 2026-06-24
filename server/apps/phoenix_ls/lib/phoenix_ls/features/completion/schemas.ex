defmodule PhoenixLS.Features.Completion.Schemas do
  @moduledoc """
  Completion items for schema-backed form fields.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    case form_field_prefix(prefix) do
      {:ok, typed_field} ->
        facts
        |> facts_by_kind(:schema_field)
        |> Enum.map(&field_item/1)
        |> prefixed_items(typed_field)

      :error ->
        []
    end
  end

  def complete(_context, _facts), do: []

  defp form_field_prefix("@form[:" <> field), do: {:ok, field}
  defp form_field_prefix(_prefix), do: :error

  defp field_item(fact) do
    name = fact.data.name

    {name,
     %CompletionItem{
       label: name,
       kind: CompletionItemKind.field(),
       detail: "field :#{name}, #{inspect(fact.data.type)}",
       insert_text: name,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "schema_field", "id" => fact.id}
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
