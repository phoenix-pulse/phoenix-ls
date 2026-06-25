defmodule PhoenixLS.Features.TemplateFacts do
  @moduledoc """
  Read-model helpers for indexed HEEx template facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Template.RenderCall
  alias PhoenixLS.Support.URI

  @type entry :: %{
          uri: String.t(),
          path: String.t(),
          name: String.t(),
          format: String.t(),
          filename: String.t()
        }

  @spec entries([Fact.t()]) :: [entry()]
  def entries(facts) when is_list(facts) do
    facts
    |> Enum.filter(&(&1.kind == :template))
    |> Enum.flat_map(&entry/1)
  end

  @spec candidate_entries([Fact.t()], String.t() | nil) :: [entry()]
  def candidate_entries(facts, nil), do: entries(facts)

  def candidate_entries(facts, uri) when is_list(facts) and is_binary(uri) do
    facts
    |> entries()
    |> Enum.filter(&candidate_template?(uri, &1))
  end

  @spec module_for_uri([Fact.t()], String.t()) :: {:ok, String.t()} | :error
  def module_for_uri(facts, uri) when is_list(facts) and is_binary(uri) do
    facts
    |> Enum.find(&(&1.kind == :template and &1.uri == uri))
    |> case do
      %Fact{data: %{module: module}} when is_binary(module) -> {:ok, module}
      _missing_template -> :error
    end
  end

  defp entry(%Fact{uri: uri}) do
    with {:ok, path} <- URI.file_uri_to_path(uri),
         {:ok, name, format} <- name_and_format(path) do
      [%{uri: uri, path: path, name: name, format: format, filename: Path.basename(path)}]
    else
      _invalid_template -> []
    end
  end

  defp name_and_format(path) do
    case Path.basename(path) |> String.split(".") do
      [name, format, "heex"] when name != "" and format != "" -> {:ok, name, format}
      [name, "heex"] when name != "" -> {:ok, name, "html"}
      _other -> :error
    end
  end

  defp candidate_template?(uri, entry) do
    uri
    |> RenderCall.candidate_uris(entry.name, entry.format)
    |> Enum.member?(entry.uri)
  end
end
