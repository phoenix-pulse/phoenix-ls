defmodule PhoenixLS.Features.PhoenixRequests.Templates do
  @moduledoc """
  Payload builder for template explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @spec list(term()) :: [map()]
  def list(facts) do
    facts
    |> Payload.facts_by_kind(:template)
    |> Enum.map(fn fact ->
      path = Payload.file_path(fact.uri)

      %{
        "name" => Map.get(fact.data, :name) || template_name(path),
        "format" => Payload.format_string(fact.data.format),
        "kind" => template_kind(fact),
        "filePath" => path,
        "location" => Payload.location(fact),
        "module" => Map.get(fact.data, :module) || template_module(path)
      }
    end)
    |> Enum.sort_by(& &1["filePath"])
  end

  defp template_kind(%Fact{data: %{kind: kind}}) when is_atom(kind), do: Atom.to_string(kind)
  defp template_kind(%Fact{data: %{kind: kind}}) when is_binary(kind), do: kind
  defp template_kind(_fact), do: "template"

  defp template_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp template_module(path) do
    path
    |> Path.split()
    |> module_parts_from_template_path()
    |> case do
      [] -> ""
      parts -> Enum.join(parts, ".")
    end
  end

  defp module_parts_from_template_path(parts) do
    case Enum.split_while(parts, &(&1 != "lib")) do
      {_before_lib, ["lib", web_root | rest]} ->
        template_dirs =
          rest
          |> Enum.drop(-1)
          |> Enum.reject(&template_context_dir?/1)

        [module_segment(web_root) | Enum.map(template_dirs, &module_segment/1)]
        |> Enum.reject(&(&1 == ""))

      _path_without_lib ->
        []
    end
  end

  defp template_context_dir?(dir), do: dir in ["controllers", "live", "templates", "components"]

  defp module_segment(segment) do
    segment
    |> String.split("_")
    |> Enum.map(&module_word/1)
    |> Enum.join()
  end

  defp module_word(""), do: ""
  defp module_word("api"), do: "API"
  defp module_word("html"), do: "HTML"
  defp module_word("json"), do: "JSON"
  defp module_word(word), do: String.capitalize(word)
end
