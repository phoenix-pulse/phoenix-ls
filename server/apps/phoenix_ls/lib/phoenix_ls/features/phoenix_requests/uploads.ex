defmodule PhoenixLS.Features.PhoenixRequests.Uploads do
  @moduledoc """
  Payload builder for LiveView upload explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @spec list(term()) :: [map()]
  def list(facts) do
    definitions = Payload.facts_by_kind(facts, :upload)
    usages = Payload.facts_by_kind(facts, :upload_usage)
    usages_by_upload = Enum.group_by(usages, &upload_key/1)
    defined_keys = MapSet.new(definitions, &upload_key/1)

    definition_payloads =
      definitions
      |> Enum.map(&upload_payload(&1, Map.get(usages_by_upload, upload_key(&1), [])))

    usage_only_payloads =
      usages
      |> Enum.reject(&MapSet.member?(defined_keys, upload_key(&1)))
      |> Enum.group_by(&upload_key/1)
      |> Enum.map(fn {{module, upload}, upload_usages} ->
        usage_only_payload(module, upload, upload_usages)
      end)

    (definition_payloads ++ usage_only_payloads)
    |> Enum.sort_by(&{&1["module"], &1["name"], &1["filePath"] || ""})
  end

  defp upload_payload(%Fact{} = fact, usages) do
    usage_payloads = usage_payloads(usages, true)

    %{
      "name" => fact.data.name,
      "module" => fact.data.module,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "options" => options_payload(fact.data.options),
      "usagesCount" => length(usage_payloads),
      "usages" => usage_payloads
    }
  end

  defp usage_only_payload(module, upload, usages) do
    usage_payloads = usage_payloads(usages, false)
    first_usage = List.first(usages)

    %{
      "name" => upload,
      "module" => module,
      "defined" => false,
      "filePath" => usage_file_path(first_usage),
      "location" => usage_location(first_usage),
      "options" => %{},
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
      "name" => fact.data.upload,
      "module" => fact.data.module,
      "role" => Atom.to_string(fact.data.role),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "defined" => defined?
    }
    |> Payload.maybe_put("attribute", fact.data.attribute)
    |> Payload.maybe_put("function", fact.data.function)
    |> Payload.maybe_put("tag", fact.data.tag)
  end

  defp options_payload(options) when is_list(options) do
    Map.new(options, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp options_payload(_options), do: %{}

  defp upload_key(%Fact{data: %{module: module, name: name}}), do: {module, name}
  defp upload_key(%Fact{data: %{module: module, upload: upload}}), do: {module, upload}

  defp usage_file_path(%Fact{} = fact), do: Payload.file_path(fact.uri)
  defp usage_file_path(_fact), do: nil

  defp usage_location(%Fact{} = fact), do: Payload.location(fact)
  defp usage_location(_fact), do: nil
end
