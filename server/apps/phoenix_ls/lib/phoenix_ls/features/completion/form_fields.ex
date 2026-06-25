defmodule PhoenixLS.Features.Completion.FormFields do
  @moduledoc """
  Completion items for schema-backed fields bound through form component variables.
  """

  alias PhoenixLS.Features.Completion.{SchemaFacts, Schemas}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      complete(source, position, context, facts)
    else
      _not_form_binding -> []
    end
  end

  @spec complete(String.t(), Positions.lsp_position(), CursorContext.t(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, %CursorContext{} = context, facts)
      when is_binary(source) and is_list(facts) do
    with {:ok, variable, field_prefix} <- form_field_context(context),
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
    |> Scope.active_tags(source, offset)
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

  defp put_form_binding(%Tag{name: ".inputs_for"} = tag, bindings, facts) do
    with %Attribute{value: variable, value_kind: :expression} <- find_attr(tag, ":let"),
         true <- identifier?(variable),
         {:ok, schema_id} <- schema_id_for_inputs_for(tag, bindings, facts) do
      Map.put(bindings, variable, schema_id)
    else
      _missing_binding -> bindings
    end
  end

  defp put_form_binding(_tag, bindings, _facts), do: bindings

  defp find_attr(%Tag{} = tag, name) do
    Enum.find(tag.attrs, &(&1.name == name))
  end

  defp schema_id_for_inputs_for(tag, bindings, facts) do
    case schema_id_for_inputs_for_field(tag, bindings, facts) do
      {:ok, schema_id} -> {:ok, schema_id}
      :error -> schema_id_for_inputs_for_source(tag, facts)
    end
  end

  defp schema_id_for_inputs_for_field(tag, bindings, facts) do
    with %Attribute{value: source, value_kind: :expression} <- find_attr(tag, "field"),
         {:ok, base_variable, path} <- form_field_path(source),
         {:ok, base_schema_id} <- Map.fetch(bindings, base_variable) do
      SchemaFacts.schema_id_for_association_path(base_schema_id, path, facts)
    else
      _not_association_field -> :error
    end
  end

  defp schema_id_for_inputs_for_source(tag, facts) do
    with %Attribute{value: source, value_kind: :expression} <- find_attr(tag, "for") do
      SchemaFacts.schema_id_for_source(source, facts)
    else
      _missing_for -> :error
    end
  end

  defp form_field_path(source) do
    with {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true),
         {:ok, base_variable, reversed_path} <- access_path(ast, []) do
      {:ok, base_variable, Enum.reverse(reversed_path)}
    else
      _not_field_access -> :error
    end
  end

  defp access_path({{:., _meta, [Access, :get]}, _call_meta, [inner_ast, segment]}, path) do
    with {:ok, segment} <- path_segment(segment) do
      access_path(inner_ast, [segment | path])
    end
  end

  defp access_path({variable, _meta, nil}, [_segment | _rest] = path) when is_atom(variable) do
    variable = Atom.to_string(variable)

    if identifier?(variable), do: {:ok, variable, path}, else: :error
  end

  defp access_path(_ast, _path), do: :error

  defp path_segment(segment) when is_atom(segment), do: {:ok, Atom.to_string(segment)}
  defp path_segment(segment) when is_binary(segment), do: {:ok, segment}
  defp path_segment(_segment), do: :error

  defp schema_id_for_form_source(source, facts) do
    SchemaFacts.schema_id_for_source(source, facts)
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
