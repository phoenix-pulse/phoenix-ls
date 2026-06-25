defmodule PhoenixLS.HEEx.Scope do
  @moduledoc """
  Helpers for resolving HEEx tag scope at a source offset.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.HEEx.Document.Attribute
  alias PhoenixLS.HEEx.Document.Tag
  alias PhoenixLS.Support.Positions

  defmodule Variable do
    @moduledoc """
    Source-ranged variable binding introduced by an active HEEx scope.
    """

    @enforce_keys [:kind, :name, :range]
    defstruct [:kind, :name, :range, :source]

    @type kind :: :for | :let
    @type source :: {:assign, String.t(), [String.t()]} | nil

    @type t :: %__MODULE__{
            kind: kind(),
            name: String.t(),
            range: Range.t(),
            source: source()
          }
  end

  @spec active_tags([Tag.t()], String.t(), non_neg_integer()) :: [Tag.t()]
  def active_tags(tags, source, offset) when is_list(tags) and is_binary(source) do
    Enum.filter(tags, &active_tag?(&1, source, offset))
  end

  @spec scoped_variables([Tag.t()], String.t(), non_neg_integer()) :: [Variable.t()]
  def scoped_variables(tags, source, offset) when is_list(tags) and is_binary(source) do
    tags
    |> active_tags(source, offset)
    |> Enum.flat_map(&tag_variables/1)
    |> prefer_inner_bindings()
  end

  defp active_tag?(%Tag{self_closing?: true}, _source, _offset), do: false

  defp active_tag?(%Tag{range: %{start: start}, closing_range: closing_range}, source, offset) do
    case Positions.lsp_position_to_offset(source, start) do
      {:ok, tag_offset} when tag_offset < offset -> before_closing?(closing_range, source, offset)
      {:ok, _tag_offset} -> false
      :error -> false
    end
  end

  defp before_closing?(nil, _source, _offset), do: true

  defp before_closing?(%{end: close_end}, source, offset) do
    case Positions.lsp_position_to_offset(source, close_end) do
      {:ok, close_offset} -> offset <= close_offset
      :error -> false
    end
  end

  defp tag_variables(%Tag{} = tag) do
    for_variables(tag) ++ let_variables(tag)
  end

  defp for_variables(%Tag{} = tag) do
    with %Attribute{value: value, value_kind: :expression} = attr <- find_attr(tag, ":for"),
         {:ok, {:<-, _meta, [pattern_ast, enumerable_ast]}} <- quoted(value) do
      source_by_name = source_by_pattern_variable(pattern_ast, enumerable_ast)

      pattern_variables(pattern_ast, attr, :for, fn name ->
        Map.get(source_by_name, name)
      end)
    else
      _not_for_binding -> []
    end
  end

  defp let_variables(%Tag{} = tag) do
    with %Attribute{value: value, value_kind: :expression} = attr <- find_attr(tag, ":let"),
         {:ok, pattern_ast} <- quoted(value) do
      pattern_variables(pattern_ast, attr, :let, fn _name -> nil end)
    else
      _not_let_binding -> []
    end
  end

  defp quoted(value) when is_binary(value) do
    Code.string_to_quoted(value, columns: true, token_metadata: true)
  end

  defp find_attr(%Tag{} = tag, name), do: Enum.find(tag.attrs, &(&1.name == name))

  defp pattern_variables(pattern_ast, %Attribute{} = attr, kind, source_fun) do
    pattern_ast
    |> variable_nodes()
    |> Enum.uniq_by(fn {name, _meta} -> name end)
    |> Enum.map(fn {name, meta} ->
      %Variable{
        kind: kind,
        name: name,
        range: variable_range(attr, name, meta),
        source: source_fun.(name)
      }
    end)
  end

  defp variable_nodes(ast) do
    {_ast, variables} =
      Macro.prewalk(ast, [], fn
        {name, meta, context} = node, acc
        when is_atom(name) and (is_atom(context) or is_nil(context)) ->
          name = Atom.to_string(name)

          if variable_identifier?(name) do
            {node, acc ++ [{name, meta}]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    variables
  end

  defp source_by_pattern_variable(pattern_ast, enumerable_ast) do
    base_source = enumerable_source(enumerable_ast)

    case {tuple_elements(pattern_ast), with_index_source(enumerable_ast)} do
      {[value_pattern, index_pattern | _rest], {:ok, indexed_source}} ->
        source_map(value_pattern, indexed_source)
        |> Map.merge(source_map(index_pattern, nil))

      _other ->
        source_map(pattern_ast, base_source)
    end
  end

  defp source_map(_pattern_ast, :error), do: %{}

  defp source_map(pattern_ast, source) do
    pattern_ast
    |> variable_nodes()
    |> Map.new(fn {name, _meta} -> {name, source} end)
  end

  defp tuple_elements({:{}, _meta, elements}) when is_list(elements), do: elements
  defp tuple_elements({left, right}), do: [left, right]
  defp tuple_elements(_ast), do: []

  defp with_index_source(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Enum]}, :with_index]}, _call_meta,
          [inner_ast | _rest]}
       ) do
    case enumerable_source(inner_ast) do
      :error -> :error
      source -> {:ok, source}
    end
  end

  defp with_index_source(_ast), do: :error

  defp enumerable_source({:@, _meta, [{assign, _assign_meta, nil}]}) when is_atom(assign) do
    assign = Atom.to_string(assign)

    if identifier?(assign), do: {:assign, assign, []}, else: :error
  end

  defp enumerable_source({{:., _meta, [inner_ast, segment]}, _call_meta, []}) do
    with {:assign, assign, path} <- enumerable_source(inner_ast),
         {:ok, segment} <- path_segment(segment) do
      {:assign, assign, path ++ [segment]}
    else
      _not_assign_path -> :error
    end
  end

  defp enumerable_source(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Enum]}, :with_index]}, _call_meta,
          [inner_ast | _rest]}
       ) do
    enumerable_source(inner_ast)
  end

  defp enumerable_source(_ast), do: :error

  defp path_segment(segment) when is_atom(segment), do: {:ok, Atom.to_string(segment)}
  defp path_segment(segment) when is_binary(segment), do: {:ok, segment}
  defp path_segment(_segment), do: :error

  defp variable_range(%Attribute{value_range: %Range{} = value_range}, name, meta) do
    line = Keyword.get(meta, :line, 1)
    column = Keyword.get(meta, :column, 1)
    line_delta = max(line - 1, 0)
    start_line = value_range.start.line + line_delta

    start_character =
      if line_delta == 0 do
        value_range.start.character + max(column - 1, 0)
      else
        max(column - 1, 0)
      end

    %Range{
      start: %Position{line: start_line, character: start_character},
      end: %Position{line: start_line, character: start_character + String.length(name)}
    }
  end

  defp variable_range(%Attribute{} = attr, _name, _meta), do: attr.value_range || attr.name_range

  defp prefer_inner_bindings(variables) do
    variables
    |> Enum.reverse()
    |> Enum.reduce({MapSet.new(), []}, fn variable, {seen, acc} ->
      if MapSet.member?(seen, variable.name) do
        {seen, acc}
      else
        {MapSet.put(seen, variable.name), [variable | acc]}
      end
    end)
    |> elem(1)
  end

  defp variable_identifier?("_"), do: false
  defp variable_identifier?("_" <> _rest), do: false
  defp variable_identifier?(value), do: identifier?(value)

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
