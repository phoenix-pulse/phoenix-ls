defmodule PhoenixLS.Features.PhoenixRequests.ColocatedAssets do
  @moduledoc """
  Payload builder for LiveView colocated asset explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @kinds [:colocated_hook, :colocated_js, :colocated_css]

  @spec list(term()) :: [map()]
  def list(snapshot) do
    assets =
      @kinds
      |> Enum.flat_map(&Payload.facts_by_kind(snapshot, &1))
      |> Enum.sort_by(&fact_position/1)

    assets
    |> Enum.group_by(& &1.data.owner_module)
    |> Enum.map(fn {owner_module, facts} -> owner_payload(owner_module, facts) end)
    |> Enum.sort_by(& &1["ownerModule"])
  end

  defp owner_payload(owner_module, facts) do
    asset_payloads = Enum.map(facts, &asset_payload/1)

    %{
      "ownerModule" => owner_module,
      "assetsCount" => length(asset_payloads),
      "assets" => asset_payloads
    }
  end

  defp asset_payload(%Fact{} = fact) do
    %{
      "kind" => Atom.to_string(fact.kind),
      "typeModule" => fact.data.type_module,
      "name" => fact.data.name,
      "generatedName" => fact.data.generated_name,
      "tag" => fact.data.tag,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "options" => fact.data.options
    }
  end

  defp fact_position(%Fact{range: range}) do
    {range.start.line, range.start.character}
  end
end
