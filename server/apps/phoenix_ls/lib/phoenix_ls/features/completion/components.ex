defmodule PhoenixLS.Features.Completion.Components do
  @moduledoc """
  Completion items for indexed Phoenix function components.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :tag_name, prefix: prefix, closing?: false}, facts) do
    cond do
      String.starts_with?(prefix, ".") -> component_tag_items(facts, prefix)
      String.starts_with?(prefix, ":") -> slot_tag_items(facts, prefix)
      remote_component_prefix?(prefix) -> remote_component_tag_items(facts, prefix)
      true -> []
    end
  end

  def complete(%CursorContext{kind: :attribute_name, tag: tag, prefix: prefix}, facts) do
    cond do
      component_tag?(tag) -> component_attr_items(facts, trim_tag_prefix(tag), prefix)
      remote_component_tag?(tag) -> remote_component_attr_items(facts, tag, prefix)
      slot_tag?(tag) -> slot_attr_items(facts, trim_tag_prefix(tag), prefix)
      true -> []
    end
  end

  def complete(_context, _facts), do: []

  defp component_tag_items(facts, prefix) do
    facts
    |> facts_by_kind(:component)
    |> Enum.map(fn fact ->
      label = "." <> fact.data.name

      {label,
       completion_item(
         label: label,
         kind: CompletionItemKind.function(),
         detail: fact.id,
         data: component_data(fact)
       )}
    end)
    |> prefixed_items(prefix)
  end

  defp remote_component_tag_items(facts, prefix) do
    facts
    |> component_aliases()
    |> Enum.flat_map(fn alias_fact ->
      facts
      |> facts_by_kind(:component)
      |> Enum.filter(&(&1.data.module == alias_fact.data.target))
      |> Enum.map(fn component_fact ->
        label = alias_fact.data.as <> "." <> component_fact.data.name

        {label,
         completion_item(
           label: label,
           kind: CompletionItemKind.function(),
           detail: component_fact.id,
           data: component_data(component_fact)
         )}
      end)
    end)
    |> prefixed_items(prefix)
  end

  defp component_attr_items(facts, component_name, prefix) do
    facts
    |> facts_by_kind(:component_attr)
    |> Enum.filter(&(&1.data.component_name == component_name))
    |> Enum.map(fn fact ->
      label = fact.data.name

      {label,
       completion_item(
         label: label,
         kind: CompletionItemKind.property(),
         detail: "attr :#{fact.data.name}, #{type_detail(fact.data.type)}",
         data: attr_data(fact)
       )}
    end)
    |> prefixed_items(prefix)
  end

  defp remote_component_attr_items(facts, tag, prefix) do
    with {:ok, module, component_name} <- remote_component_module(facts, tag) do
      facts
      |> facts_by_kind(:component_attr)
      |> Enum.filter(&(&1.data.module == module and &1.data.component_name == component_name))
      |> Enum.map(fn fact ->
        label = fact.data.name

        {label,
         completion_item(
           label: label,
           kind: CompletionItemKind.property(),
           detail: "attr :#{fact.data.name}, #{type_detail(fact.data.type)}",
           data: attr_data(fact)
         )}
      end)
      |> prefixed_items(prefix)
    else
      :error -> []
    end
  end

  defp slot_tag_items(facts, prefix) do
    facts
    |> facts_by_kind(:component_slot)
    |> Enum.map(fn fact ->
      label = ":" <> fact.data.name

      {label,
       completion_item(
         label: label,
         kind: CompletionItemKind.field(),
         detail: "slot :#{fact.data.name}",
         data: %{"kind" => "component_slot", "id" => fact.id}
       )}
    end)
    |> prefixed_items(prefix)
  end

  defp slot_attr_items(facts, slot_name, prefix) do
    facts
    |> facts_by_kind(:component_slot_attr)
    |> Enum.filter(&(&1.data.slot == slot_name))
    |> Enum.map(fn fact ->
      label = fact.data.name

      {label,
       completion_item(
         label: label,
         kind: CompletionItemKind.property(),
         detail: "slot attr :#{fact.data.name}, #{type_detail(fact.data.type)}",
         data: %{"kind" => "component_slot_attr", "id" => fact.id}
       )}
    end)
    |> prefixed_items(prefix)
  end

  defp completion_item(opts) do
    %CompletionItem{
      label: Keyword.fetch!(opts, :label),
      kind: Keyword.fetch!(opts, :kind),
      detail: Keyword.fetch!(opts, :detail),
      insert_text: Keyword.fetch!(opts, :label),
      insert_text_format: InsertTextFormat.plain_text(),
      data: Keyword.fetch!(opts, :data)
    }
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end

  defp component_aliases(facts) do
    facts_by_kind(facts, :component_alias)
  end

  defp component_tag?("." <> _name), do: true
  defp component_tag?(_tag), do: false

  defp slot_tag?(":" <> _name), do: true
  defp slot_tag?(_tag), do: false

  defp trim_tag_prefix("." <> name), do: name
  defp trim_tag_prefix(":" <> name), do: name

  defp remote_component_prefix?(prefix) when is_binary(prefix) do
    remote_component_tag?(prefix)
  end

  defp remote_component_tag?(tag) when is_binary(tag) do
    case String.split(tag, ".", parts: 2) do
      [alias_name, component_name] -> alias_name != "" and component_name != ""
      _other -> false
    end
  end

  defp remote_component_tag?(_tag), do: false

  defp remote_component_module(facts, tag) do
    case String.split(tag, ".", parts: 2) do
      [alias_name, component_name] ->
        case Enum.find(component_aliases(facts), &(&1.data.as == alias_name)) do
          nil -> :error
          alias_fact -> {:ok, alias_fact.data.target, component_name}
        end

      _other ->
        :error
    end
  end

  defp component_data(fact) do
    %{"kind" => "component", "id" => fact.id}
    |> maybe_put("documentation", Map.get(fact.data, :doc))
  end

  defp attr_data(fact) do
    %{"kind" => "component_attr", "id" => fact.id}
    |> maybe_put("documentation", option_value(fact.data.options, :doc))
  end

  defp option_value(options, key) do
    Keyword.get(options || [], key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp type_detail(type), do: inspect(type)
end
