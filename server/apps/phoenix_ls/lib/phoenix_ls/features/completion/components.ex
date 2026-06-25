defmodule PhoenixLS.Features.Completion.Components do
  @moduledoc """
  Completion items for indexed Phoenix function components.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

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

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      complete(source, position, context, facts)
    else
      _invalid_context -> []
    end
  end

  defp complete(
         source,
         position,
         %CursorContext{kind: :tag_name, prefix: prefix, closing?: false} = context,
         facts
       ) do
    if String.starts_with?(prefix || "", ":") do
      with %Fact{} = component <- active_component(source, position, facts) do
        slot_tag_items(facts, prefix, component.id)
      else
        _no_active_component -> []
      end
    else
      complete(context, facts)
    end
  end

  defp complete(
         source,
         position,
         %CursorContext{kind: :attribute_name, tag: tag, prefix: prefix} = context,
         facts
       ) do
    if slot_tag?(tag) do
      with %Fact{} = component <- active_component(source, position, facts) do
        slot_attr_items(facts, trim_tag_prefix(tag), prefix, component.id)
      else
        _no_active_component -> []
      end
    else
      complete(context, facts)
    end
  end

  defp complete(_source, _position, %CursorContext{} = context, facts),
    do: complete(context, facts)

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
    |> ComponentLookup.remote_component_entries()
    |> Enum.map(fn {label, component_fact} ->
      {label,
       completion_item(
         label: label,
         kind: CompletionItemKind.function(),
         detail: component_fact.id,
         data: component_data(component_fact)
       )}
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
    with %Fact{} = component <- ComponentLookup.component_for_tag(tag, facts) do
      facts
      |> facts_by_kind(:component_attr)
      |> Enum.filter(&(&1.data.component == component.id))
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
      nil -> []
    end
  end

  defp slot_tag_items(facts, prefix, component_id \\ nil) do
    facts
    |> facts_by_kind(:component_slot)
    |> filter_component(component_id)
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

  defp slot_attr_items(facts, slot_name, prefix, component_id \\ nil) do
    facts
    |> facts_by_kind(:component_slot_attr)
    |> Enum.filter(&(&1.data.slot == slot_name))
    |> filter_component(component_id)
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

  defp filter_component(facts, nil), do: facts

  defp filter_component(facts, component_id),
    do: Enum.filter(facts, &(&1.data.component == component_id))

  defp active_component(source, position, facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source) do
      document.tags
      |> Scope.active_tags(source, offset)
      |> Enum.reverse()
      |> Enum.find_value(fn tag ->
        if tag.kind in [:component, :remote_component] do
          ComponentLookup.component_for_tag(tag.name, facts)
        end
      end)
    else
      _unavailable_scope -> nil
    end
  end

  defp component_tag?("." <> _name), do: true
  defp component_tag?(_tag), do: false

  defp slot_tag?(":" <> _name), do: true
  defp slot_tag?(_tag), do: false

  defp trim_tag_prefix("." <> name), do: name
  defp trim_tag_prefix(":" <> name), do: name

  defp remote_component_prefix?(prefix) when is_binary(prefix) do
    ComponentLookup.remote_component_tag?(prefix)
  end

  defp remote_component_tag?(tag) when is_binary(tag) do
    ComponentLookup.remote_component_tag?(tag)
  end

  defp remote_component_tag?(_tag), do: false

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
