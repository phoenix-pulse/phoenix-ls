defmodule PhoenixLS.Introspection.Template.Hooks do
  @moduledoc """
  Extracts source-ranged LiveView hook usage facts from parsed HEEx documents.
  """

  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks

  @spec facts(String.t(), Document.t(), map(), map()) :: [Fact.t()]
  def facts(uri, %Document{} = document, metadata, provenance)
      when is_binary(uri) and is_map(metadata) and is_map(provenance) do
    module = Map.get(metadata, :module, "")

    document.tags
    |> Enum.flat_map(&tag_facts(&1, uri, module, provenance))
    |> Enum.sort_by(&fact_position/1)
  end

  defp tag_facts(%Tag{name: tag_name, attrs: attrs}, uri, module, provenance) do
    attrs
    |> Enum.filter(&hook_attr?/1)
    |> Enum.filter(&literal_attr_value?/1)
    |> Enum.reject(&blank?(&1.value))
    |> Enum.map(&hook_usage_fact(&1, uri, module, tag_name, provenance))
  end

  defp hook_usage_fact(%Attribute{} = attr, uri, module, tag_name, provenance) do
    range = attr.value_range || attr.name_range

    Fact.new!(
      kind: :hook_usage,
      id: hook_usage_id(uri, attr.value, range),
      uri: uri,
      range: range,
      provenance: provenance,
      data: %Hooks.HookUsage{
        module: module,
        name: attr.value,
        attribute: attr.name,
        tag: tag_name
      }
    )
  end

  defp hook_usage_id(uri, name, range) do
    position = range.start

    "#{uri}:hook_usage:#{name}:#{position.line}:#{position.character}"
  end

  defp hook_attr?(%Attribute{name: "phx-hook"}), do: true
  defp hook_attr?(_attr), do: false

  defp literal_attr_value?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_attr_value?(_attr), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp fact_position(%Fact{range: range, data: data}) do
    {range.start.line, range.start.character, data.name}
  end
end
