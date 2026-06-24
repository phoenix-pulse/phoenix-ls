defmodule PhoenixLS.Features.Completion.Snippets do
  @moduledoc """
  Small static Phoenix and HTML completion set.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @html_tags ["div", "span", "button", "form", "section", "article"]
  @phoenix_attrs ["phx-click", "phx-change", "phx-submit", "phx-target", "phx-value-"]

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :tag_name, prefix: prefix, closing?: false}, _facts) do
    prefix = prefix || ""

    if snippet_tag_prefix?(prefix) do
      @html_tags
      |> Enum.map(&tag_item/1)
      |> prefixed_items(prefix)
    else
      []
    end
  end

  def complete(%CursorContext{kind: :attribute_name, prefix: prefix}, _facts) do
    @phoenix_attrs
    |> Enum.map(&attribute_item/1)
    |> prefixed_items(prefix || "")
  end

  def complete(_context, _facts), do: []

  defp snippet_tag_prefix?("." <> _prefix), do: false
  defp snippet_tag_prefix?(":" <> _prefix), do: false
  defp snippet_tag_prefix?(""), do: true

  defp snippet_tag_prefix?(<<first::utf8, _rest::binary>>) do
    first not in ?A..?Z
  end

  defp tag_item(tag) do
    {tag,
     %CompletionItem{
       label: tag,
       kind: CompletionItemKind.snippet(),
       detail: "HTML <#{tag}>",
       insert_text: tag,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "html_tag", "id" => tag}
     }}
  end

  defp attribute_item(attribute) do
    {attribute,
     %CompletionItem{
       label: attribute,
       kind: CompletionItemKind.property(),
       detail: "Phoenix attribute",
       insert_text: attribute,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "phoenix_attr", "id" => attribute}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
