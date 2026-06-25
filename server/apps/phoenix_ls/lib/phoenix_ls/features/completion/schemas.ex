defmodule PhoenixLS.Features.Completion.Schemas do
  @moduledoc """
  Completion items for schema-backed form fields.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.HEEx.CursorContext

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    case form_field_prefix(prefix) do
      {:ok, typed_field} ->
        field_items(facts, typed_field)

      :error ->
        []
    end
  end

  def complete(_context, _facts), do: []

  @spec field_items([PhoenixLS.Index.Fact.t()], String.t(), String.t() | nil) :: [
          CompletionItem.t()
        ]
  def field_items(facts, typed_field, schema_id \\ nil) when is_list(facts) do
    facts
    |> Facts.by_kind(:schema_field)
    |> filter_schema(schema_id)
    |> Enum.map(&field_item/1)
    |> prefixed_items(typed_field)
  end

  @spec property_items([PhoenixLS.Index.Fact.t()], String.t(), String.t() | nil) :: [
          CompletionItem.t()
        ]
  def property_items(facts, typed_property, schema_id \\ nil) when is_list(facts) do
    facts
    |> Facts.by_kind(:schema_field)
    |> Kernel.++(Facts.by_kind(facts, :schema_association))
    |> filter_schema(schema_id)
    |> Enum.map(&property_item/1)
    |> prefixed_items(typed_property)
  end

  defp form_field_prefix("@form[:" <> field), do: {:ok, field}
  defp form_field_prefix(_prefix), do: :error

  defp filter_schema(facts, nil), do: facts
  defp filter_schema(facts, schema_id), do: Enum.filter(facts, &(&1.data.schema == schema_id))

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

  defp property_item(%Fact{kind: :schema_field} = fact), do: field_item(fact)

  defp property_item(%Fact{kind: :schema_association} = fact) do
    name = fact.data.name

    {name,
     %CompletionItem{
       label: name,
       kind: CompletionItemKind.reference(),
       detail: "#{fact.data.association} :#{name}, #{fact.data.related}",
       insert_text: name,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "schema_association", "id" => fact.id}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
