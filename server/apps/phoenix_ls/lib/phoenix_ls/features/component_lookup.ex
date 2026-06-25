defmodule PhoenixLS.Features.ComponentLookup do
  @moduledoc """
  Shared lookup helpers for indexed Phoenix component facts.
  """

  alias PhoenixLS.Index.Fact

  @spec component_for_tag(String.t() | nil, [Fact.t()]) :: Fact.t() | nil
  def component_for_tag("." <> component_name, facts) do
    find_component(facts, component_name)
  end

  def component_for_tag(tag, facts) when is_binary(tag) do
    with {:ok, alias_name, component_name} <- remote_component_tag(tag),
         %Fact{} = alias_fact <- find_component_alias(facts, alias_name) do
      find_component(facts, alias_fact.data.target, component_name)
    else
      _not_remote_component -> nil
    end
  end

  def component_for_tag(_tag, _facts), do: nil

  @spec slot_for_tag(String.t() | nil, [Fact.t()]) :: Fact.t() | nil
  def slot_for_tag(":" <> slot_prefix, facts) do
    Enum.find(
      facts_by_kind(facts, :component_slot),
      &String.starts_with?(&1.data.name, slot_prefix)
    )
  end

  def slot_for_tag(_tag, _facts), do: nil

  @spec component_attr_for_tag(String.t() | nil, String.t(), [Fact.t()]) :: Fact.t() | nil
  def component_attr_for_tag(tag, prefix, facts) do
    with %Fact{} = component <- component_for_tag(tag, facts) do
      Enum.find(
        facts_by_kind(facts, :component_attr),
        &(&1.data.component == component.id and String.starts_with?(&1.data.name, prefix))
      )
    end
  end

  @spec slot_attr_for_tag(String.t() | nil, String.t(), [Fact.t()]) :: Fact.t() | nil
  def slot_attr_for_tag(tag, prefix, facts) do
    with %Fact{} = slot <- slot_for_tag(tag, facts) do
      Enum.find(
        facts_by_kind(facts, :component_slot_attr),
        &(&1.data.slot == slot.data.name and String.starts_with?(&1.data.name, prefix))
      )
    end
  end

  @spec remote_component_entries([Fact.t()]) :: [{String.t(), Fact.t()}]
  def remote_component_entries(facts) do
    facts
    |> facts_by_kind(:component_alias)
    |> Enum.flat_map(fn alias_fact ->
      facts
      |> facts_by_kind(:component)
      |> Enum.filter(&(&1.data.module == alias_fact.data.target))
      |> Enum.map(&{alias_fact.data.as <> "." <> &1.data.name, &1})
    end)
  end

  @spec remote_component_tag?(String.t() | nil) :: boolean()
  def remote_component_tag?(tag) when is_binary(tag) do
    match?({:ok, _alias_name, _component_name}, remote_component_tag(tag))
  end

  def remote_component_tag?(_tag), do: false

  defp find_component(facts, component_name) do
    Enum.find(facts_by_kind(facts, :component), &(&1.data.name == component_name))
  end

  defp find_component(facts, module, component_name) do
    Enum.find(
      facts_by_kind(facts, :component),
      &(&1.data.module == module and &1.data.name == component_name)
    )
  end

  defp find_component_alias(facts, alias_name) do
    Enum.find(facts_by_kind(facts, :component_alias), &(&1.data.as == alias_name))
  end

  defp remote_component_tag(tag) do
    case String.split(tag, ".", parts: 2) do
      [alias_name, component_name] when alias_name != "" and component_name != "" ->
        {:ok, alias_name, component_name}

      _other ->
        :error
    end
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
