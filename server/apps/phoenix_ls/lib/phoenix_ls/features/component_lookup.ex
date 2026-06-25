defmodule PhoenixLS.Features.ComponentLookup do
  @moduledoc """
  Shared lookup helpers for indexed Phoenix component facts.
  """

  alias PhoenixLS.HEEx.{Parser, Scope}
  alias PhoenixLS.HEEx.Document.Tag
  alias PhoenixLS.Features.{Facts, TemplateFacts}
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

  @spec component_for_tag(String.t() | nil, [Fact.t()], String.t() | nil) :: Fact.t() | nil
  def component_for_tag(tag, facts, nil), do: component_for_tag(tag, facts)

  def component_for_tag("." <> component_name, facts, module) when is_binary(module) do
    find_available_component(facts, component_name, module)
  end

  def component_for_tag(tag, facts, _module), do: component_for_tag(tag, facts)

  @spec unavailable_local_component(String.t() | nil, [Fact.t()], String.t() | nil) ::
          Fact.t() | nil
  def unavailable_local_component("." <> component_name, facts, module) when is_binary(module) do
    candidate = find_component(facts, component_name)

    if candidate && !component_available?(candidate, module, facts) do
      candidate
    else
      nil
    end
  end

  def unavailable_local_component(_tag, _facts, _module), do: nil

  @spec module_for_uri([Fact.t()], String.t() | nil) :: String.t() | nil
  def module_for_uri(_facts, nil), do: nil

  def module_for_uri(facts, uri) when is_list(facts) and is_binary(uri) do
    case TemplateFacts.module_for_uri(facts, uri) do
      {:ok, module} ->
        module

      :error ->
        facts
        |> Enum.find(fn
          %Fact{kind: :module, uri: ^uri, data: %{module: module}} when is_binary(module) -> true
          _fact -> false
        end)
        |> case do
          %Fact{data: %{module: module}} -> module
          _missing_module -> nil
        end
    end
  end

  @spec component_for_source_tag(String.t() | nil, String.t(), Positions.lsp_position(), [
          Fact.t()
        ]) :: Fact.t() | nil
  def component_for_source_tag(tag_prefix, source, position, facts)
      when is_binary(tag_prefix) and is_binary(source) and is_list(facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source),
         %Tag{} = tag <-
           tag_at_offset(document.tags, source, offset, [:component, :remote_component]) do
      component_for_tag(tag.name, facts)
    else
      _not_on_component_tag -> nil
    end
  end

  def component_for_source_tag(_tag_prefix, _source, _position, _facts), do: nil

  @spec component_for_source_tag(
          String.t() | nil,
          String.t() | nil,
          String.t(),
          Positions.lsp_position(),
          [Fact.t()]
        ) :: Fact.t() | nil
  def component_for_source_tag(uri, tag_prefix, source, position, facts)
      when is_binary(tag_prefix) and is_binary(source) and is_list(facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source),
         %Tag{} = tag <-
           tag_at_offset(document.tags, source, offset, [:component, :remote_component]) do
      component_for_tag(tag.name, facts, module_for_uri(facts, uri))
    else
      _not_on_component_tag -> nil
    end
  end

  def component_for_source_tag(_uri, _tag_prefix, _source, _position, _facts), do: nil

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
        Facts.by_kind(facts, :component_attr),
        &(&1.data.component == component.id and String.starts_with?(&1.data.name, prefix))
      )
    end
  end

  @spec component_attr_for_tag(String.t() | nil, String.t(), [Fact.t()], String.t() | nil) ::
          Fact.t() | nil
  def component_attr_for_tag(tag, prefix, facts, module) do
    with %Fact{} = component <- component_for_tag(tag, facts, module) do
      Enum.find(
        Facts.by_kind(facts, :component_attr),
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
    |> Facts.by_kind(:component_alias)
    |> Enum.flat_map(fn alias_fact ->
      facts
      |> Facts.by_kind(:component)
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

  @spec active_component(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) ::
          Fact.t() | nil
  def active_component(uri, source, position, facts)
      when is_binary(source) and is_list(facts) do
    module = module_for_uri(facts, uri)

    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source) do
      document.tags
      |> Scope.active_tags(source, offset)
      |> Enum.reverse()
      |> Enum.find_value(&component_for_document_tag(&1, facts, module))
    else
      _unavailable_scope -> nil
    end
  end

  defp find_component(facts, component_name) do
    Enum.find(Facts.by_kind(facts, :component), &(&1.data.name == component_name))
  end

  defp find_component(facts, module, component_name) do
    Enum.find(
      Facts.by_kind(facts, :component),
      &(&1.data.module == module and &1.data.name == component_name)
    )
  end

  defp find_available_component(facts, component_name, module) do
    facts
    |> Facts.by_kind(:component)
    |> Enum.find(&(&1.data.name == component_name and component_available?(&1, module, facts)))
  end

  defp component_available?(%Fact{data: %{module: module}}, module, _facts), do: true

  defp component_available?(%Fact{} = component, module, facts) do
    direct_import_allows_component?(component, module, facts) or
      macro_import_allows_component?(component, module, facts)
  end

  defp direct_import_allows_component?(component, module, facts) do
    facts
    |> Facts.by_kind(:component_import)
    |> Enum.any?(&import_allows_component?(&1, component, module))
  end

  defp import_allows_component?(
         %Fact{data: %{module: module, target: target, only: only, except: except}},
         %Fact{data: %{module: target, name: component_name}},
         module
       ) do
    import_option_allows?(only, component_name) and
      not import_option_blocks?(except, component_name)
  end

  defp import_allows_component?(_import, _component, _module), do: false

  defp macro_import_allows_component?(component, module, facts) do
    facts
    |> Facts.by_kind(:component_use)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.any?(&web_macro_import_allows_component?(&1, component, facts))
  end

  defp web_macro_import_allows_component?(
         %Fact{data: %{target: web_module, macro: macro}},
         %Fact{} = component,
         facts
       ) do
    facts
    |> Facts.by_kind(:component_macro_import)
    |> Enum.any?(&macro_import_allows_component?(&1, component, web_module, macro))
  end

  defp macro_import_allows_component?(
         %Fact{
           data: %{module: web_module, macro: macro, target: target, only: only, except: except}
         },
         %Fact{data: %{module: target, name: component_name}},
         web_module,
         macro
       ) do
    import_option_allows?(only, component_name) and
      not import_option_blocks?(except, component_name)
  end

  defp macro_import_allows_component?(_import, _component, _web_module, _macro), do: false

  defp import_option_allows?(nil, _component_name), do: true

  defp import_option_allows?(entries, component_name) when is_list(entries) do
    Enum.any?(entries, &import_entry_matches?(&1, component_name))
  end

  defp import_option_allows?(_other, _component_name), do: true

  defp import_option_blocks?(nil, _component_name), do: false

  defp import_option_blocks?(entries, component_name) when is_list(entries) do
    Enum.any?(entries, &import_entry_matches?(&1, component_name))
  end

  defp import_option_blocks?(_other, _component_name), do: false

  defp import_entry_matches?({name, 1}, component_name) when is_atom(name),
    do: Atom.to_string(name) == component_name

  defp import_entry_matches?({name, 1}, component_name) when is_binary(name),
    do: name == component_name

  defp import_entry_matches?(_entry, _component_name), do: false

  defp find_component_alias(facts, alias_name) do
    Enum.find(Facts.by_kind(facts, :component_alias), &(&1.data.as == alias_name))
  end

  defp find_slot(facts, slot_prefix) do
    Enum.find(
      Facts.by_kind(facts, :component_slot),
      &String.starts_with?(&1.data.name, slot_prefix)
    )
  end

  defp find_component_slot(facts, component_id, slot_prefix) do
    Enum.find(
      Facts.by_kind(facts, :component_slot),
      &(&1.data.component == component_id and String.starts_with?(&1.data.name, slot_prefix))
    )
  end

  defp find_slot_attr(facts, %Fact{} = slot, prefix) do
    Enum.find(
      Facts.by_kind(facts, :component_slot_attr),
      &(&1.data.component == slot.data.component and &1.data.slot == slot.data.name and
          String.starts_with?(&1.data.name, prefix))
    )
  end

  defp tag_at_offset(tags, source, offset, kinds) do
    Enum.find(tags, fn
      %Tag{kind: kind, name_range: range} ->
        kind in kinds and range_contains_offset?(range, source, offset)

      _tag ->
        false
    end)
  end

  defp range_contains_offset?(%{start: start_position, end: end_position}, source, offset) do
    with {:ok, start_offset} <- Positions.lsp_position_to_offset(source, start_position),
         {:ok, end_offset} <- Positions.lsp_position_to_offset(source, end_position) do
      start_offset <= offset and offset <= end_offset
    else
      _invalid_range -> false
    end
  end

  defp component_for_document_tag(%Tag{kind: kind, name: name}, facts)
       when kind in [:component, :remote_component] do
    component_for_tag(name, facts)
  end

  defp component_for_document_tag(_tag, _facts), do: nil

  defp component_for_document_tag(%Tag{kind: kind, name: name}, facts, module)
       when kind in [:component, :remote_component] do
    component_for_tag(name, facts, module)
  end

  defp component_for_document_tag(_tag, _facts, _module), do: nil

  defp remote_component_tag(tag) do
    case String.split(tag, ".", parts: 2) do
      [alias_name, component_name] when alias_name != "" and component_name != "" ->
        {:ok, alias_name, component_name}

      _other ->
        :error
    end
  end
end
