defmodule PhoenixLS.Features.Completion.ColocatedAssets do
  @moduledoc """
  Completion items for LiveView colocated asset type modules.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Template.ColocatedAssets

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{} = context, facts) when is_list(facts) do
    complete_source_context(context)
  end

  defp complete_source_context(%CursorContext{
         kind: :expression,
         tag: tag,
         attribute: ":type",
         prefix: prefix
       }) do
    ColocatedAssets.type_definitions()
    |> Enum.filter(&(&1.tag == tag))
    |> Enum.filter(&String.starts_with?(&1.type_module, prefix || ""))
    |> Enum.map(&type_item/1)
  end

  defp complete_source_context(_context), do: []

  defp type_item(definition) do
    %CompletionItem{
      label: definition.type_module,
      kind: CompletionItemKind.module(),
      detail: "LiveView colocated #{type_label(definition.kind)}",
      insert_text: definition.type_module,
      insert_text_format: InsertTextFormat.plain_text(),
      data: %{
        "kind" => "colocated_asset_type",
        "type" => Atom.to_string(definition.kind)
      }
    }
  end

  defp type_label(:colocated_hook), do: "hook"
  defp type_label(:colocated_js), do: "JavaScript"
  defp type_label(:colocated_css), do: "CSS"
end
