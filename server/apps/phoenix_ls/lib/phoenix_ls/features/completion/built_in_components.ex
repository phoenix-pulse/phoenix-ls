defmodule PhoenixLS.Features.Completion.BuiltInComponents do
  @moduledoc """
  Completion items for Phoenix.Component function components that are imported by `use Phoenix.*`.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.BuiltInComponents, as: BuiltIns
  alias PhoenixLS.HEEx.CursorContext

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :tag_name, prefix: prefix, closing?: false}, _facts) do
    prefix = prefix || ""

    BuiltIns.all()
    |> Enum.map(&component_item/1)
    |> prefixed_items(prefix)
  end

  def complete(
        %CursorContext{kind: :attribute_name, tag: "." <> component_name, prefix: prefix},
        _facts
      ) do
    with %{name: ^component_name} = component <- BuiltIns.component_for_tag("." <> component_name) do
      component
      |> component_attr_items()
      |> prefixed_items(prefix || "")
    else
      _unknown_component -> []
    end
  end

  def complete(_context, _facts), do: []

  defp component_item(component) do
    label = "." <> component.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.function(),
       detail: component.id,
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "phoenix_component", "id" => component.id}
     }}
  end

  defp component_attr_items(component) do
    component
    |> BuiltIns.attrs()
    |> Enum.map(&component_attr_item(component, &1))
  end

  defp component_attr_item(component, attr) do
    {attr.name,
     %CompletionItem{
       label: attr.name,
       kind: CompletionItemKind.property(),
       detail: attr.detail,
       insert_text: attr.insert_text,
       insert_text_format: insert_text_format(attr),
       data: %{"kind" => "phoenix_component_attr", "id" => attr_id(component, attr.name)}
     }}
  end

  defp insert_text_format(%{insert_text_format: value}) when is_integer(value), do: value
  defp insert_text_format(%{insert_text_format: :plain_text}), do: InsertTextFormat.plain_text()
  defp insert_text_format(_attr), do: InsertTextFormat.snippet()

  defp attr_id(component, attr_name), do: "#{component.id}:attr:#{attr_name}"

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
