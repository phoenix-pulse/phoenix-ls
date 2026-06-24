defmodule PhoenixLS.Features.Completion.ElixirFallback do
  @moduledoc """
  Narrow generic Elixir fallback completions for expression contexts.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @functions [
    {"to_string", "Kernel.to_string/1"},
    {"inspect", "Kernel.inspect/1"},
    {"is_nil", "Kernel.is_nil/1"}
  ]

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, _facts) do
    if phoenix_specific_expression?(prefix || "") do
      []
    else
      @functions
      |> Enum.map(&function_item/1)
      |> prefixed_items(prefix || "")
    end
  end

  def complete(_context, _facts), do: []

  defp phoenix_specific_expression?("@" <> _rest), do: true
  defp phoenix_specific_expression?("~p\"" <> _rest), do: true
  defp phoenix_specific_expression?("~p'" <> _rest), do: true
  defp phoenix_specific_expression?("@form[:" <> _rest), do: true
  defp phoenix_specific_expression?(_prefix), do: false

  defp function_item({label, detail}) do
    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.function(),
       detail: detail,
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "elixir_fallback", "id" => label}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
