defmodule PhoenixLS.Features.ComponentLookup do
  @moduledoc """
  Shared lookup helpers for indexed Phoenix component facts.
  """

  alias PhoenixLS.HEEx.{Parser, Scope}
  alias PhoenixLS.HEEx.Document.Tag
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

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
    find_slot(facts, slot_prefix)
  end

  def slot_for_tag(_tag, _facts), do: nil

  @spec slot_for_source_tag(String.t() | nil, String.t(), Positions.lsp_position(), [
          Fact.t()
        ]) :: Fact.t() | nil
  def slot_for_source_tag(":" <> slot_prefix, source, position, facts) do
    with %Fact{} = component <- active_component(source, position, facts) do
      find_component_slot(facts, component.id, slot_prefix)
    end
  end

  def slot_for_source_tag(_tag, _source, _position, _facts), do: nil

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
      find_slot_attr(facts, slot, prefix)
    end
  end

  @spec slot_attr_for_source_tag(
          String.t() | nil,
          String.t(),
          String.t(),
          Positions.lsp_position(),
          [Fact.t()]
        ) :: Fact.t() | nil
  def slot_attr_for_source_tag(tag, prefix, source, position, facts) do
    with %Fact{} = slot <- slot_for_source_tag(tag, source, position, facts) do
      find_slot_attr(facts, slot, prefix)
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

  @spec active_component(String.t(), Positions.lsp_position(), [Fact.t()]) :: Fact.t() | nil
  def active_component(source, position, facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source) do
      document.tags
      |> Scope.active_tags(source, offset)
      |> Enum.reverse()
      |> Enum.find_value(&component_for_document_tag(&1, facts))
    else
      _unavailable_scope -> nil
    end
  end

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

  defp find_slot(facts, slot_prefix) do
    Enum.find(
      facts_by_kind(facts, :component_slot),
      &String.starts_with?(&1.data.name, slot_prefix)
    )
  end

  defp find_component_slot(facts, component_id, slot_prefix) do
    Enum.find(
      facts_by_kind(facts, :component_slot),
      &(&1.data.component == component_id and String.starts_with?(&1.data.name, slot_prefix))
    )
  end

  defp find_slot_attr(facts, %Fact{} = slot, prefix) do
    Enum.find(
      facts_by_kind(facts, :component_slot_attr),
      &(&1.data.component == slot.data.component and &1.data.slot == slot.data.name and
          String.starts_with?(&1.data.name, prefix))
    )
  end

  defp component_for_document_tag(%Tag{kind: kind, name: name}, facts)
       when kind in [:component, :remote_component] do
    component_for_tag(name, facts)
  end

  defp component_for_document_tag(_tag, _facts), do: nil

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
