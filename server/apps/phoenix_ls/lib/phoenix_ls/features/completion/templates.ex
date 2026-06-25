defmodule PhoenixLS.Features.Completion.Templates do
  @moduledoc """
  Completion items for controller `render(conn, :template)` calls.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Template.RenderCall
  alias PhoenixLS.Support.{Positions, URI}

  @sentinel "__phoenix_ls_template_completion__"

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, completion_source, prefix} <- completion_source(source, offset),
         {:ok, tokens} <- RenderCall.tokenize_prefix(completion_source),
         {:ok, index} <- sentinel_index(tokens),
         true <- RenderCall.template_argument?(tokens, index) do
      template_items(uri, prefix, facts)
    else
      _not_template_completion -> []
    end
  end

  defp completion_source(source, offset) do
    prefix = binary_part(source, 0, offset)
    start_offset = atom_name_start(prefix, byte_size(prefix))

    cond do
      start_offset > 0 and :binary.at(prefix, start_offset - 1) == ?: ->
        atom_prefix = binary_part(prefix, start_offset, byte_size(prefix) - start_offset)
        source_before_atom = binary_part(prefix, 0, start_offset)
        {:ok, source_before_atom <> @sentinel, atom_prefix}

      true ->
        :error
    end
  end

  defp atom_name_start(source, offset) when offset > 0 do
    previous_offset = offset - 1

    if atom_name_char?(:binary.at(source, previous_offset)) do
      atom_name_start(source, previous_offset)
    else
      offset
    end
  end

  defp atom_name_start(_source, offset), do: offset

  defp atom_name_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char == ?_
  end

  defp sentinel_index(tokens) do
    tokens
    |> Enum.find_index(&sentinel_token?/1)
    |> case do
      nil -> :error
      index -> {:ok, index}
    end
  end

  defp sentinel_token?({:atom, _meta, sentinel}), do: Atom.to_string(sentinel) == @sentinel
  defp sentinel_token?(_token), do: false

  defp template_items(uri, prefix, facts) do
    facts
    |> Enum.filter(&(&1.kind == :template))
    |> Enum.flat_map(&template_entry/1)
    |> Enum.filter(&(&1.format == "html"))
    |> Enum.filter(&String.starts_with?(&1.name, prefix))
    |> Enum.filter(&candidate_template?(uri, &1))
    |> Enum.sort_by(&{&1.name, &1.uri})
    |> Enum.map(&template_item/1)
  end

  defp template_entry(%Fact{uri: uri}) do
    with {:ok, path} <- URI.file_uri_to_path(uri),
         {:ok, name, format} <- template_name_and_format(path) do
      [%{uri: uri, path: path, name: name, format: format}]
    else
      _invalid_template -> []
    end
  end

  defp template_name_and_format(path) do
    case Path.basename(path) |> String.split(".") do
      [name, format, "heex"] when name != "" and format != "" -> {:ok, name, format}
      [name, "heex"] when name != "" -> {:ok, name, "html"}
      _other -> :error
    end
  end

  defp candidate_template?(nil, _entry), do: true

  defp candidate_template?(uri, entry) do
    uri
    |> RenderCall.candidate_uris(entry.name, entry.format)
    |> Enum.member?(entry.uri)
  end

  defp template_item(entry) do
    label = ":" <> entry.name

    %CompletionItem{
      label: label,
      kind: CompletionItemKind.value(),
      detail: "Template file: #{Path.basename(entry.path)}",
      insert_text: entry.name,
      insert_text_format: InsertTextFormat.plain_text(),
      data: %{
        "kind" => "template",
        "template" => entry.name,
        "format" => entry.format,
        "uri" => entry.uri
      }
    }
  end
end
