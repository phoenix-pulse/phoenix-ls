defmodule PhoenixLS.Features.Completion.PhxValues do
  @moduledoc """
  Context-aware `phx-value-*` completions for schema-backed `:for` loops.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.SchemaFacts
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, %CursorContext{kind: :attribute_name, prefix: "phx-value-" <> prefix}} <-
           CursorContext.at(source, position),
         {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source),
         {:ok, loop} <- enclosing_loop(document.tags, source, offset),
         {:ok, schema_id} <- schema_id_for_loop(loop, facts) do
      schema_id
      |> SchemaFacts.schema_fields(facts)
      |> Enum.filter(&String.starts_with?(&1.data.name, prefix))
      |> Enum.map(&field_item(&1, loop.variable))
    else
      _not_phx_value_context -> []
    end
  end

  defp enclosing_loop(tags, source, offset) do
    tags
    |> Scope.active_tags(source, offset)
    |> Enum.reverse()
    |> Enum.reduce_while(:error, fn tag, _acc ->
      case loop_binding(tag) do
        {:ok, loop} -> {:halt, {:ok, loop}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp loop_binding(%Tag{} = tag) do
    with %Attribute{value: source, value_kind: :expression} <- find_attr(tag, ":for"),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true),
         {:ok, variable, source_ref} <- loop_ast(ast) do
      {:ok, %{variable: variable, source: source_ref}}
    else
      _not_loop -> :error
    end
  end

  defp find_attr(%Tag{} = tag, name), do: Enum.find(tag.attrs, &(&1.name == name))

  defp loop_ast({:<-, _meta, [left_ast, right_ast]}) do
    with {:ok, variable} <- loop_variable(left_ast),
         {:ok, source_ref} <- loop_source(right_ast) do
      {:ok, variable, source_ref}
    end
  end

  defp loop_ast(_ast), do: :error

  defp loop_variable({variable, _meta, nil}) when is_atom(variable) do
    variable = Atom.to_string(variable)

    if identifier?(variable), do: {:ok, variable}, else: :error
  end

  defp loop_variable({first_ast, _second_ast}), do: loop_variable(first_ast)
  defp loop_variable({:{}, _meta, [first_ast | _rest]}), do: loop_variable(first_ast)
  defp loop_variable(_ast), do: :error

  defp loop_source({:@, _meta, [{assign, _assign_meta, nil}]}) when is_atom(assign) do
    assign = Atom.to_string(assign)

    if identifier?(assign), do: {:ok, {:assign, assign, []}}, else: :error
  end

  defp loop_source({{:., _meta, [inner_ast, segment]}, _call_meta, []}) do
    with {:ok, {:assign, assign, path}} <- loop_source(inner_ast),
         {:ok, segment} <- path_segment(segment) do
      {:ok, {:assign, assign, path ++ [segment]}}
    end
  end

  defp loop_source(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Enum]}, :with_index]}, _call_meta,
          [
            inner_ast | _rest
          ]}
       ) do
    loop_source(inner_ast)
  end

  defp loop_source(_ast), do: :error

  defp path_segment(segment) when is_atom(segment), do: {:ok, Atom.to_string(segment)}
  defp path_segment(segment) when is_binary(segment), do: {:ok, segment}
  defp path_segment(_segment), do: :error

  defp schema_id_for_loop(%{source: {:assign, assign, []}}, facts) do
    SchemaFacts.schema_id_for_assign(assign, facts)
  end

  defp schema_id_for_loop(%{source: {:assign, assign, path}}, facts) do
    with {:ok, base_schema_id} <- SchemaFacts.schema_id_for_assign(assign, facts) do
      SchemaFacts.schema_id_for_association_path(base_schema_id, path, facts)
    end
  end

  defp field_item(%Fact{} = fact, variable) do
    field = fact.data.name

    %CompletionItem{
      label: "phx-value-#{field}",
      kind: CompletionItemKind.property(),
      detail: "From #{variable}: #{inspect(fact.data.type)}",
      insert_text: "phx-value-#{field}={#{variable}.#{field}}",
      insert_text_format: InsertTextFormat.plain_text(),
      data: %{"kind" => "phx_value_field", "id" => fact.id}
    }
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
