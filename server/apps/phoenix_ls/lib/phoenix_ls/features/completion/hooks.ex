defmodule PhoenixLS.Features.Completion.Hooks do
  @moduledoc """
  Completion items for LiveView JavaScript hook names.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(
        %CursorContext{kind: :attribute_value, attribute: "phx-hook", prefix: prefix},
        facts
      )
      when is_list(facts) do
    facts
    |> Hooks.definitions()
    |> Enum.map(&hook_item/1)
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  def complete(_context, _facts), do: []

  defp hook_item(%Fact{} = fact) do
    label = Hooks.hook_name(fact)

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.property(),
       detail: "LiveView hook #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "hook", "id" => fact.id}
     }}
  end
end
