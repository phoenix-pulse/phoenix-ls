defmodule PhoenixLS.Features.Completion.FormFields do
  @moduledoc """
  Completion items for schema-backed fields bound through `<.form :let={...}>`.
  """

  alias PhoenixLS.Features.Completion.Schemas
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position),
         {:ok, variable, field_prefix} <- form_field_context(context),
         {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source),
         {:ok, schema_id} <- schema_for_binding(document.tags, source, offset, variable, facts) do
      Schemas.field_items(facts, field_prefix, schema_id)
    else
      _not_form_binding -> []
    end
  end

  defp form_field_context(%CursorContext{kind: :expression, prefix: prefix})
       when is_binary(prefix) do
    case String.split(prefix, "[:", parts: 2) do
      [variable, field_prefix] ->
        if identifier?(variable), do: {:ok, variable, field_prefix}, else: :error

      _other ->
        :error
    end
  end

  defp form_field_context(_context), do: :error

  defp schema_for_binding(tags, source, offset, variable, facts) do
    tags
    |> Enum.filter(&tag_before?(&1, source, offset))
    |> Enum.reduce(%{}, &put_form_binding(&1, &2, facts))
    |> Map.fetch(variable)
  end

  defp put_form_binding(%Tag{name: ".form"} = tag, bindings, facts) do
    with %Attribute{value: variable, value_kind: :expression} <- find_attr(tag, ":let"),
         true <- identifier?(variable),
         %Attribute{value: source, value_kind: :expression} <- find_attr(tag, "for"),
         {:ok, schema_id} <- schema_id_for_form_source(source, facts) do
      Map.put(bindings, variable, schema_id)
    else
      _missing_binding -> bindings
    end
  end

  defp put_form_binding(_tag, bindings, _facts), do: bindings

  defp tag_before?(%Tag{range: %{start: start}}, source, offset) do
    case Positions.lsp_position_to_offset(source, start) do
      {:ok, tag_offset} -> tag_offset < offset
      :error -> false
    end
  end

  defp find_attr(%Tag{} = tag, name) do
    Enum.find(tag.attrs, &(&1.name == name))
  end

  defp schema_id_for_form_source(source, facts) do
    with {:ok, candidate} <- schema_candidate(source) do
      facts
      |> Enum.filter(&(&1.kind == :schema))
      |> Enum.find(&schema_match?(&1, candidate))
      |> case do
        %Fact{id: schema_id} -> {:ok, schema_id}
        nil -> :error
      end
    end
  end

  defp schema_candidate("@" <> assign), do: camelized_candidate(assign)
  defp schema_candidate(":" <> atom), do: camelized_candidate(atom)
  defp schema_candidate(_source), do: :error

  defp camelized_candidate(value) do
    if identifier?(value) do
      {:ok,
       value
       |> String.split("_")
       |> Enum.map_join("", &String.capitalize/1)}
    else
      :error
    end
  end

  defp schema_match?(%Fact{data: %{module: module}}, candidate) do
    module == candidate or String.ends_with?(module, "." <> candidate)
  end

  defp identifier?(<<first::utf8, rest::binary>>) do
    identifier_start?(first) and rest_identifier?(rest)
  end

  defp identifier?(_value), do: false

  defp rest_identifier?(<<char::utf8, rest::binary>>) do
    identifier_char?(char) and rest_identifier?(rest)
  end

  defp rest_identifier?(""), do: true

  defp identifier_start?(char), do: char == ?_ or lower?(char) or upper?(char)
  defp identifier_char?(char), do: identifier_start?(char) or digit?(char)

  defp lower?(char), do: char >= ?a and char <= ?z
  defp upper?(char), do: char >= ?A and char <= ?Z
  defp digit?(char), do: char >= ?0 and char <= ?9
end
