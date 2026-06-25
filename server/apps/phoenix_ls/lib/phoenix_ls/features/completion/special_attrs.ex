defmodule PhoenixLS.Features.Completion.SpecialAttrs do
  @moduledoc """
  Completion metadata for HEEx special attributes.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @attrs [
    %{
      label: ":for",
      detail: "HEEx comprehension",
      insert_text: ":for={${1:item} <- ${2:@items}}",
      format: InsertTextFormat.snippet()
    },
    %{
      label: ":if",
      detail: "HEEx conditional render",
      insert_text: ":if={${1:@condition}}",
      format: InsertTextFormat.snippet()
    },
    %{
      label: ":let",
      detail: "HEEx yielded value binding",
      insert_text: ":let={${1:var}}",
      format: InsertTextFormat.snippet()
    },
    %{
      label: ":key",
      detail: "HEEx keyed comprehension item",
      insert_text: ":key={${1:item.id}}",
      format: InsertTextFormat.snippet()
    },
    %{
      label: "phx-no-format",
      detail: "Disable HEEx formatter for this element",
      insert_text: "phx-no-format",
      format: InsertTextFormat.plain_text()
    }
  ]

  @spec complete(CursorContext.t()) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :attribute_name, prefix: prefix}) do
    @attrs
    |> Enum.map(&item/1)
    |> prefixed_items(prefix || "")
  end

  def complete(%CursorContext{}), do: []

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name), do: Enum.any?(@attrs, &(&1.label == name))
  def known?(_name), do: false

  defp item(%{label: label, detail: detail, insert_text: insert_text, format: format}) do
    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.property(),
       detail: detail,
       insert_text: insert_text,
       insert_text_format: format,
       data: %{"kind" => "heex_special_attr", "id" => label}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> special_attr_visible?(label, prefix) end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp special_attr_visible?("phx-no-format", prefix) do
    String.starts_with?("phx-no-format", prefix) and String.starts_with?(prefix, "phx-no")
  end

  defp special_attr_visible?(label, prefix), do: String.starts_with?(label, prefix)
end
