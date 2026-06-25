defmodule PhoenixLS.Features.Diagnostics.Components do
  @moduledoc """
  Diagnostics for Phoenix function components, slots, and LiveComponents.
  """

  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.Features.Diagnostics.ComponentValues
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact

  @live_component_required_attrs ["id", "module"]
  @global_component_attrs ["id", "class", "style", "title", ":for", ":if", ":let", ":key"]
  @global_slot_attrs [":for", ":if", ":let", ":key"]
  @global_prefix_attrs ["aria-", "data-"]

  @spec diagnostics(Tag.t(), map(), [Tag.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Tag{kind: :component, name: ".live_component"} = tag, _indexes, _tags) do
    live_component_diagnostics(tag)
  end

  def diagnostics(%Tag{kind: kind} = tag, indexes, tags)
      when kind in [:component, :remote_component] do
    case ComponentLookup.component_for_tag(tag.name, indexes.facts, indexes.module) do
      %Fact{} = component ->
        known_component_diagnostics(tag, component, indexes, tags)

      nil ->
        case ComponentLookup.unavailable_local_component(tag.name, indexes.facts, indexes.module) do
          %Fact{} = component -> [not_imported_diagnostic(tag, component, indexes.module)]
          nil -> []
        end
    end
  end

  def diagnostics(%Tag{kind: :slot} = tag, indexes, tags) do
    slot_name = String.trim_leading(tag.name, ":")

    case parent_component(tag, tags, indexes.facts) do
      %Fact{} = component ->
        case slot_for_component(component, slot_name, indexes) do
          %Fact{} = slot ->
            known_slot_diagnostics(tag, slot, indexes)

          nil ->
            [
              Builder.diagnostic(
                tag.name_range,
                "phoenix.unknown_slot",
                ~s(Unknown slot "#{tag.name}")
              )
            ]
        end

      nil ->
        []
    end
  end

  def diagnostics(%Tag{}, _indexes, _tags), do: []

  defp known_component_diagnostics(%Tag{} = tag, %Fact{} = component, indexes, tags) do
    attrs = Map.get(indexes.attrs_by_component, component.id, [])
    present_attr_names = MapSet.new(tag.attrs, & &1.name)

    missing_required_attr_diagnostics(tag, attrs, present_attr_names) ++
      missing_required_slot_diagnostics(tag, component, indexes, tags) ++
      unknown_attr_diagnostics(tag, attrs) ++
      ComponentValues.diagnostics(tag, attrs)
  end

  defp not_imported_diagnostic(%Tag{} = tag, %Fact{} = component, module) do
    Builder.diagnostic(
      tag.name_range,
      "phoenix.component_not_imported",
      ~s(Component #{tag.name} is not imported in #{module}),
      %{
        "kind" => "component_not_imported",
        "tag" => tag.name,
        "component" => component.data.name,
        "module" => module
      }
    )
  end

  defp known_slot_diagnostics(%Tag{} = tag, %Fact{} = slot, indexes) do
    attrs = slot_attrs(slot, indexes)
    present_attr_names = MapSet.new(tag.attrs, & &1.name)

    missing_required_attr_diagnostics(tag, attrs, present_attr_names) ++
      unknown_slot_attr_diagnostics(tag, attrs) ++
      ComponentValues.diagnostics(tag, attrs)
  end

  defp missing_required_attr_diagnostics(%Tag{} = tag, attrs, present_attr_names) do
    attrs
    |> Enum.filter(&required_attr?/1)
    |> Enum.reject(&MapSet.member?(present_attr_names, &1.data.name))
    |> Enum.map(fn attr ->
      Builder.diagnostic(
        tag.name_range,
        "phoenix.missing_required_attr",
        ~s(Missing required attr "#{attr.data.name}" for #{tag.name}),
        %{
          "kind" => "missing_required_attr",
          "tag" => tag.name,
          "attr" => attr.data.name
        }
      )
    end)
  end

  defp missing_required_slot_diagnostics(%Tag{} = tag, %Fact{} = component, indexes, tags) do
    present_slot_names = present_slot_names(tag, tags)

    indexes.slots_by_component
    |> Map.get(component.id, [])
    |> Enum.filter(&required_attr?/1)
    |> Enum.reject(&MapSet.member?(present_slot_names, &1.data.name))
    |> Enum.map(fn slot ->
      Builder.diagnostic(
        tag.name_range,
        "phoenix.missing_required_slot",
        ~s(Missing required slot ":#{slot.data.name}" for #{tag.name}),
        %{
          "kind" => "missing_required_slot",
          "tag" => tag.name,
          "slot" => slot.data.name
        }
      )
    end)
  end

  defp parent_component(%Tag{} = slot_tag, tags, facts) do
    tags
    |> Enum.filter(&(&1.kind in [:component, :remote_component]))
    |> Enum.filter(&tag_inside?(slot_tag, &1))
    |> Enum.reverse()
    |> Enum.find_value(&ComponentLookup.component_for_tag(&1.name, facts))
  end

  defp slot_for_component(%Fact{} = component, slot_name, indexes) do
    indexes.slots_by_component
    |> Map.get(component.id, [])
    |> Enum.find(&(&1.data.name == slot_name))
  end

  defp slot_attrs(%Fact{} = slot, indexes) do
    indexes.attrs_by_slot
    |> Map.get(slot.data.name, [])
    |> Enum.filter(&(&1.data.component == slot.data.component))
  end

  defp present_slot_names(%Tag{} = component_tag, tags) do
    explicit_slot_names =
      tags
      |> Enum.filter(&(&1.kind == :slot))
      |> Enum.filter(&tag_inside?(&1, component_tag))
      |> MapSet.new(&String.trim_leading(&1.name, ":"))

    if default_inner_block_present?(component_tag) do
      MapSet.put(explicit_slot_names, "inner_block")
    else
      explicit_slot_names
    end
  end

  defp default_inner_block_present?(%Tag{self_closing?: false, closing_range: %{}}), do: true
  defp default_inner_block_present?(_tag), do: false

  defp tag_inside?(
         %Tag{range: %{start: slot_start}},
         %Tag{range: %{start: component_start}, closing_range: %{start: component_end}}
       ) do
    position_after?(slot_start, component_start) and position_before?(slot_start, component_end)
  end

  defp tag_inside?(_slot_tag, _component_tag), do: false

  defp position_after?(first, second) do
    compare_positions(first, second) == :gt
  end

  defp position_before?(first, second) do
    compare_positions(first, second) == :lt
  end

  defp compare_positions(%{line: line, character: character}, %{
         line: other_line,
         character: other_character
       }) do
    cond do
      line > other_line -> :gt
      line < other_line -> :lt
      character > other_character -> :gt
      character < other_character -> :lt
      true -> :eq
    end
  end

  defp unknown_attr_diagnostics(%Tag{} = tag, attrs) do
    declared_attr_names = MapSet.new(attrs, & &1.data.name)

    tag.attrs
    |> Enum.reject(&known_component_attr?(&1, declared_attr_names, attrs))
    |> Enum.map(fn attr ->
      Builder.diagnostic(
        attr.name_range,
        "phoenix.unknown_attr",
        ~s(Unknown attr "#{attr.name}" for #{tag.name})
      )
    end)
  end

  defp unknown_slot_attr_diagnostics(%Tag{} = tag, attrs) do
    declared_attr_names = MapSet.new(attrs, & &1.data.name)

    tag.attrs
    |> Enum.reject(&known_slot_attr?(&1, declared_attr_names, attrs))
    |> Enum.map(fn attr ->
      Builder.diagnostic(
        attr.name_range,
        "phoenix.unknown_attr",
        ~s(Unknown attr "#{attr.name}" for #{tag.name})
      )
    end)
  end

  defp live_component_diagnostics(%Tag{} = tag) do
    present_attr_names = MapSet.new(tag.attrs, & &1.name)

    @live_component_required_attrs
    |> Enum.reject(&MapSet.member?(present_attr_names, &1))
    |> Enum.map(fn attr_name ->
      Builder.diagnostic(
        tag.name_range,
        "phoenix.missing_live_component_attr",
        ~s(Missing required attr "#{attr_name}" for .live_component),
        %{
          "kind" => "missing_live_component_attr",
          "tag" => ".live_component",
          "attr" => attr_name
        }
      )
    end)
  end

  defp known_component_attr?(%Attribute{} = attr, declared_attr_names, attrs) do
    dynamic_attr?(attr) or
      MapSet.member?(declared_attr_names, attr.name) or
      global_component_attr?(attr) or
      global_include_attr?(attr, attrs)
  end

  defp known_slot_attr?(%Attribute{} = attr, declared_attr_names, attrs) do
    dynamic_attr?(attr) or
      MapSet.member?(declared_attr_names, attr.name) or
      global_slot_attr?(attr) or
      global_component_attr?(attr) or
      global_include_attr?(attr, attrs)
  end

  defp dynamic_attr?(%Attribute{name: "{" <> _dynamic}), do: true
  defp dynamic_attr?(%Attribute{}), do: false

  defp global_include_attr?(%Attribute{name: name}, attrs) do
    Enum.any?(attrs, fn
      %Fact{data: %{type: :global, options: options}} ->
        options
        |> Keyword.get(:include, [])
        |> List.wrap()
        |> Enum.member?(name)

      _attr ->
        false
    end)
  end

  defp global_component_attr?(%Attribute{name: name}) do
    name in @global_component_attrs or
      String.starts_with?(name, @global_prefix_attrs) or
      String.starts_with?(name, "phx-")
  end

  defp global_slot_attr?(%Attribute{name: name}) do
    name in @global_slot_attrs
  end

  defp required_attr?(%Fact{data: %{options: options}}) do
    Keyword.get(options || [], :required, false) == true
  end
end
