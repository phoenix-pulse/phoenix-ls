defmodule PhoenixLS.Features.ComponentDocs do
  @moduledoc """
  Shared markdown builders for Phoenix component facts.
  """

  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Index.Fact

  @spec component_markdown(Fact.t(), [Fact.t()]) :: String.t()
  def component_markdown(%Fact{kind: :component} = component, facts) when is_list(facts) do
    attrs = component_attrs(component, facts)
    slots = component_slots(component, facts)

    [
      code("component #{component.id}"),
      "Phoenix function component",
      Map.get(component.data, :doc),
      source_line(component),
      attr_section(attrs),
      slot_section(slots)
    ]
    |> compact_join()
  end

  @spec attr_markdown(Fact.t()) :: String.t()
  def attr_markdown(%Fact{kind: :component_attr} = attr) do
    attr_markdown(attr.data)
  end

  @spec attr_markdown(map()) :: String.t()
  def attr_markdown(%{name: name, type: type, options: options}) do
    [
      code("attr :#{name}, #{inspect(type)}"),
      required_line(options),
      option_lines(options),
      Keyword.get(options || [], :doc)
    ]
    |> compact_join()
  end

  def attr_markdown(%{detail: detail} = attr) do
    [
      code(detail),
      Map.get(attr, :doc)
    ]
    |> compact_join()
  end

  @spec built_in_component_markdown(map(), [map()]) :: String.t()
  def built_in_component_markdown(component, attrs) when is_map(component) and is_list(attrs) do
    [
      code("component #{component.id}"),
      component.doc,
      "Source: Phoenix.Component",
      attr_section(attrs)
    ]
    |> compact_join()
  end

  @spec slot_markdown(Fact.t(), [Fact.t()]) :: String.t()
  def slot_markdown(%Fact{kind: :component_slot} = slot, facts) when is_list(facts) do
    attrs =
      facts
      |> Facts.by_kind(:component_slot_attr)
      |> Enum.filter(
        &(&1.data.component == slot.data.component and &1.data.slot == slot.data.name)
      )

    [
      "Slot `:#{slot.data.name}`",
      code("slot :#{slot.data.name}"),
      option_lines(slot.data.options),
      Keyword.get(slot.data.options || [], :doc),
      code("component #{slot.data.component}"),
      slot_attr_section(attrs),
      slot_example(slot)
    ]
    |> compact_join()
  end

  @spec slot_attr_markdown(Fact.t()) :: String.t()
  def slot_attr_markdown(%Fact{kind: :component_slot_attr} = attr) do
    [
      code("slot attr :#{attr.data.name}, #{inspect(attr.data.type)}"),
      "slot :#{attr.data.slot}",
      required_line(attr.data.options),
      option_lines(attr.data.options),
      Keyword.get(attr.data.options || [], :doc),
      attr.data.component
    ]
    |> compact_join()
  end

  defp component_attrs(component, facts) do
    facts
    |> Facts.by_kind(:component_attr)
    |> Enum.filter(&(&1.data.component == component.id))
  end

  defp source_line(%Fact{data: data}) do
    case Map.get(data, :module) do
      module when is_binary(module) -> "Source: #{module}"
      _missing_module -> nil
    end
  end

  defp component_slots(component, facts) do
    facts
    |> Facts.by_kind(:component_slot)
    |> Enum.filter(&(&1.data.component == component.id))
  end

  defp attr_section([]), do: nil

  defp attr_section(attrs) do
    attrs
    |> Enum.map(&attr_markdown/1)
    |> section("Attributes")
  end

  defp slot_section([]), do: nil

  defp slot_section(slots) do
    slots
    |> Enum.map(fn slot ->
      [
        code("slot :#{slot.data.name}"),
        option_lines(slot.data.options)
      ]
      |> compact_join()
    end)
    |> section("Slots")
  end

  defp slot_attr_section([]), do: nil

  defp slot_attr_section(attrs) do
    attrs
    |> Enum.map(&slot_attr_markdown/1)
    |> section("Slot Attributes")
  end

  defp slot_example(%Fact{data: %{name: name}}) do
    [
      "Example",
      "```heex\n<:#{name}>\n  ...\n</:#{name}>\n```"
    ]
    |> compact_join()
  end

  defp section(entries, title) do
    [title | entries]
    |> compact_join()
  end

  defp option_lines(options) do
    options
    |> List.wrap()
    |> Enum.reject(fn {key, _value} -> key == :doc end)
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> compact_join()
  end

  defp required_line(options) do
    if Keyword.get(options || [], :required, false) == true do
      "Required"
    else
      "Optional"
    end
  end

  defp code(value) do
    "```elixir\n#{value}\n```"
  end

  defp compact_join(values) do
    values
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
