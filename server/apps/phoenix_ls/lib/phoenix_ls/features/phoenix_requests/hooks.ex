defmodule PhoenixLS.Features.PhoenixRequests.Hooks do
  @moduledoc """
  Payload builder for LiveView hook explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks

  @spec list(term()) :: [map()]
  def list(snapshot) do
    definitions = Payload.facts_by_kind(snapshot, :hook)
    usages = Payload.facts_by_kind(snapshot, :hook_usage)
    usages_by_name = Enum.group_by(usages, &Hooks.hook_name/1)
    defined_names = MapSet.new(definitions, &Hooks.hook_name/1)

    definition_payloads =
      definitions
      |> Enum.map(&hook_payload(&1, Map.get(usages_by_name, Hooks.hook_name(&1), [])))

    usage_only_payloads =
      usages
      |> Enum.reject(&MapSet.member?(defined_names, Hooks.hook_name(&1)))
      |> Enum.group_by(&Hooks.hook_name/1)
      |> Enum.map(fn {name, hook_usages} ->
        usage_only_payload(name, hook_usages)
      end)

    (definition_payloads ++ usage_only_payloads)
    |> Enum.sort_by(&{&1["name"], defined_rank(&1), &1["filePath"] || ""})
  end

  defp hook_payload(%Fact{} = fact, usages) do
    usage_payloads = usage_payloads(usages, true)

    %{
      "name" => fact.data.name,
      "defined" => true,
      "source" => source_string(fact.data.source),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "usagesCount" => length(usage_payloads),
      "usages" => usage_payloads
    }
  end

  defp usage_only_payload(name, usages) do
    usage_payloads = usage_payloads(usages, false)
    first_usage = List.first(usages)

    %{
      "name" => name,
      "defined" => false,
      "filePath" => usage_file_path(first_usage),
      "location" => usage_location(first_usage),
      "usagesCount" => length(usage_payloads),
      "usages" => usage_payloads
    }
  end

  defp usage_payloads(usages, defined?) do
    usages
    |> Enum.map(&usage_payload(&1, defined?))
    |> Enum.sort_by(&{&1["filePath"], &1["location"]["line"], &1["location"]["character"]})
  end

  defp usage_payload(%Fact{} = fact, defined?) do
    %{
      "name" => fact.data.name,
      "module" => fact.data.module,
      "attribute" => fact.data.attribute,
      "tag" => fact.data.tag,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "defined" => defined?
    }
  end

  defp source_string(source) when is_atom(source), do: Atom.to_string(source)
  defp source_string(source) when is_binary(source), do: source
  defp source_string(source), do: inspect(source)

  defp usage_file_path(%Fact{} = fact), do: Payload.file_path(fact.uri)
  defp usage_file_path(_fact), do: nil

  defp usage_location(%Fact{} = fact), do: Payload.location(fact)
  defp usage_location(_fact), do: nil

  defp defined_rank(%{"defined" => false}), do: 0
  defp defined_rank(_payload), do: 1
end
