defmodule PhoenixLS.Features.PhoenixRequests.Components do
  @moduledoc """
  Payload builder for component explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload

  @spec list(term()) :: [map()]
  def list(facts) do
    attrs_by_component =
      facts
      |> Payload.facts_by_kind(:component_attr)
      |> Enum.group_by(& &1.data.component)

    slots_by_component =
      facts
      |> Payload.facts_by_kind(:component_slot)
      |> Enum.group_by(& &1.data.component)

    slot_attrs_by_component =
      facts
      |> Payload.facts_by_kind(:component_slot_attr)
      |> Enum.group_by(& &1.data.component)

    facts
    |> Payload.facts_by_kind(:component)
    |> Enum.map(fn fact ->
      attrs = Map.get(attrs_by_component, fact.id, [])
      slots = Map.get(slots_by_component, fact.id, [])
      slot_attrs = Map.get(slot_attrs_by_component, fact.id, [])

      %{
        "name" => fact.data.name,
        "module" => fact.data.module,
        "filePath" => Payload.file_path(fact.uri),
        "location" => Payload.location(fact),
        "attributesCount" => length(attrs),
        "slotsCount" => length(slots),
        "attributes" => Enum.map(attrs, &component_attr_payload/1),
        "slots" => Enum.map(slots, &component_slot_payload(&1, slot_attrs))
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp component_attr_payload(fact) do
    fact.data.options
    |> Payload.option_payload()
    |> Map.merge(%{
      "name" => fact.data.name,
      "type" => Payload.type_string(fact.data.type),
      "required" => Payload.required?(fact.data.options),
      "rawType" => inspect(fact.data.type),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    })
  end

  defp component_slot_payload(slot, slot_attrs) do
    attrs =
      slot_attrs
      |> Enum.filter(&(&1.data.slot == slot.data.name))
      |> Enum.map(&component_attr_payload/1)

    slot.data.options
    |> Payload.option_payload()
    |> Map.merge(%{
      "name" => slot.data.name,
      "required" => Payload.required?(slot.data.options),
      "filePath" => Payload.file_path(slot.uri),
      "location" => Payload.location(slot),
      "attributes" => attrs
    })
  end
end
