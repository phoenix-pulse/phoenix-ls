defmodule PhoenixLS.Introspection.Router.HelperReferences do
  @moduledoc """
  Extracts source-ranged `Routes.*_path` and `Routes.*_url` references.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Parsing.{ElixirTokens, SourceMap}
  alias PhoenixLS.Support.Positions

  defmodule Reference do
    @moduledoc """
    Typed route helper reference payload.
    """

    @enforce_keys [:helper, :helper_base, :variant, :arity]
    defstruct [
      :helper,
      :helper_base,
      :variant,
      :action,
      :action_range,
      :arg_insert_range,
      :arg_trim_ranges,
      :arity
    ]
  end

  @spec facts(term(), String.t(), keyword()) :: [Fact.t()]
  def facts(quoted, uri, opts \\ []) when is_binary(uri) do
    facts(quoted, uri, nil, opts)
  end

  @spec facts(term(), String.t(), String.t() | nil, keyword()) :: [Fact.t()]
  def facts(quoted, uri, source, opts) when is_binary(uri) do
    tokens = source_tokens(source)

    {_ast, facts} =
      Macro.prewalk(quoted, [], fn
        node, acc ->
          {node, helper_fact(node, uri, source, tokens, opts) ++ acc}
      end)

    Enum.reverse(facts)
  end

  defp helper_fact(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Routes]}, helper_atom]}, call_meta,
          args},
         uri,
         source,
         tokens,
         opts
       )
       when is_atom(helper_atom) and is_list(args) do
    helper = Atom.to_string(helper_atom)
    action = helper_action(args)

    with {:ok, helper_base, variant} <- helper_parts(helper),
         {:ok, range} <- helper_range(call_meta, helper) do
      [
        Fact.new!(
          kind: :route_helper_reference,
          id: route_helper_reference_id(uri, range),
          uri: uri,
          range: range,
          provenance: provenance(opts),
          data: %Reference{
            helper: helper,
            helper_base: helper_base,
            variant: variant,
            action: action,
            action_range: helper_action_range(source, tokens, call_meta, helper_atom, action),
            arg_insert_range: helper_arg_insert_range(source, tokens, call_meta, helper_atom),
            arg_trim_ranges: helper_arg_trim_ranges(source, tokens, call_meta, helper_atom),
            arity: length(args)
          }
        )
      ]
    else
      _not_route_helper -> []
    end
  end

  defp helper_fact(_node, _uri, _source, _tokens, _opts), do: []

  defp helper_action([_conn_or_socket, action | _rest]) when is_atom(action), do: action
  defp helper_action(_args), do: nil

  defp source_tokens(source) when is_binary(source) do
    case ElixirTokens.tokenize(source) do
      {:ok, tokens} -> tokens
      :error -> nil
    end
  end

  defp source_tokens(_source), do: nil

  defp helper_action_range(source, tokens, call_meta, helper, action)
       when is_binary(source) and is_list(tokens) and is_atom(helper) and is_atom(action) do
    with {:ok, helper_index} <- helper_token_index(tokens, call_meta, helper),
         {:ok, token} <- second_argument_token(tokens, helper_index),
         true <- atom_token_value(token) == action,
         {:ok, range} <- atom_token_range(source, token) do
      range
    else
      _no_action_range -> nil
    end
  end

  defp helper_action_range(_source, _tokens, _call_meta, _helper, _action), do: nil

  defp helper_arg_insert_range(source, tokens, call_meta, helper)
       when is_binary(source) and is_list(tokens) and is_atom(helper) do
    with {:ok, helper_index} <- helper_token_index(tokens, call_meta, helper),
         {:ok, _commas, token} <- call_argument_boundary_tokens(tokens, helper_index),
         {:ok, offset} <- token_start_offset(source, token_meta(token)),
         {:ok, range} <- SourceMap.to_lsp_range(SourceMap.new(source), offset, offset) do
      range
    else
      _no_insert_range -> nil
    end
  end

  defp helper_arg_insert_range(_source, _tokens, _call_meta, _helper), do: nil

  defp helper_arg_trim_ranges(source, tokens, call_meta, helper)
       when is_binary(source) and is_list(tokens) and is_atom(helper) do
    with {:ok, helper_index} <- helper_token_index(tokens, call_meta, helper),
         {:ok, commas, closing_token} <- call_argument_boundary_tokens(tokens, helper_index),
         {:ok, end_offset} <- token_start_offset(source, token_meta(closing_token)) do
      commas
      |> Enum.with_index(1)
      |> Map.new(fn {comma, keep_count} ->
        {:ok, start_offset} = token_start_offset(source, token_meta(comma))
        {:ok, range} = SourceMap.to_lsp_range(SourceMap.new(source), start_offset, end_offset)

        {keep_count, range}
      end)
    else
      _no_trim_ranges -> %{}
    end
  end

  defp helper_arg_trim_ranges(_source, _tokens, _call_meta, _helper), do: nil

  defp helper_token_index(tokens, call_meta, helper) do
    line = Keyword.get(call_meta, :line)
    column = Keyword.get(call_meta, :column)

    case Enum.find_index(tokens, &helper_token?(&1, line, column, helper)) do
      nil -> :error
      index -> {:ok, index}
    end
  end

  defp helper_token?({type, {line, column, _chars}, value}, line, column, helper)
       when type in [:identifier, :paren_identifier] do
    value == helper
  end

  defp helper_token?(_token, _line, _column, _helper), do: false

  defp second_argument_token(tokens, helper_index) do
    case Enum.at(tokens, helper_index + 1) do
      {:"(", _meta} -> find_argument_token(tokens, helper_index + 2, 0, 0)
      _not_parenthesized -> :error
    end
  end

  defp call_argument_boundary_tokens(tokens, helper_index) do
    case Enum.at(tokens, helper_index + 1) do
      {:"(", _meta} -> find_call_argument_boundaries(tokens, helper_index + 2, 0, [])
      _not_parenthesized -> :error
    end
  end

  defp find_call_argument_boundaries(tokens, index, depth, commas) do
    case Enum.at(tokens, index) do
      nil ->
        :error

      token ->
        find_call_argument_boundaries(tokens, index, depth, commas, token, token_type(token))
    end
  end

  defp find_call_argument_boundaries(_tokens, _index, 0, commas, token, :")") do
    {:ok, Enum.reverse(commas), token}
  end

  defp find_call_argument_boundaries(tokens, index, 0, commas, token, :",") do
    find_call_argument_boundaries(tokens, index + 1, 0, [token | commas])
  end

  defp find_call_argument_boundaries(tokens, index, depth, commas, _token, type) do
    cond do
      opening_token?(type) ->
        find_call_argument_boundaries(tokens, index + 1, depth + 1, commas)

      closing_token?(type) ->
        find_call_argument_boundaries(tokens, index + 1, depth - 1, commas)

      true ->
        find_call_argument_boundaries(tokens, index + 1, depth, commas)
    end
  end

  defp find_argument_token(tokens, index, depth, argument_index) do
    case Enum.at(tokens, index) do
      nil ->
        :error

      token ->
        find_argument_token(tokens, index, depth, argument_index, token, token_type(token))
    end
  end

  defp find_argument_token(tokens, index, depth, argument_index, token, type) do
    cond do
      closing_token?(type) and depth == 0 ->
        :error

      argument_index == 1 and depth == 0 and value_token?(type) ->
        {:ok, token}

      type == :"," and depth == 0 ->
        find_argument_token(tokens, index + 1, depth, argument_index + 1)

      opening_token?(type) ->
        find_argument_token(tokens, index + 1, depth + 1, argument_index)

      closing_token?(type) ->
        find_argument_token(tokens, index + 1, depth - 1, argument_index)

      true ->
        find_argument_token(tokens, index + 1, depth, argument_index)
    end
  end

  defp value_token?(type), do: type not in [:eol, :","]

  defp opening_token?(type), do: type in [:"(", :"[", :"{", :"%{"]
  defp closing_token?(type), do: type in [:")", :"]", :"}"]

  defp atom_token_value({:atom, _meta, value}), do: value
  defp atom_token_value(_token), do: nil

  defp atom_token_range(source, {:atom, meta, _value}) do
    with {:ok, start_offset} <- token_start_offset(source, meta),
         {:ok, end_offset} <- atom_token_end_offset(source, start_offset, meta) do
      SourceMap.to_lsp_range(SourceMap.new(source), start_offset, end_offset)
    end
  end

  defp token_start_offset(source, {line, column, _chars}) do
    Positions.lsp_position_to_offset(source, %{line: line - 1, character: column - 1})
  end

  defp atom_token_end_offset(source, start_offset, {_line, _column, chars}) when is_list(chars) do
    case :binary.at(source, start_offset) do
      ?: -> {:ok, start_offset + 1 + byte_size(IO.iodata_to_binary(chars))}
      _other -> :error
    end
  end

  defp atom_token_end_offset(_source, _start_offset, _meta), do: :error

  defp token_meta({_type, meta}), do: meta
  defp token_meta({_type, meta, _value}), do: meta

  defp token_type({type, _meta}), do: type
  defp token_type({type, _meta, _value}), do: type

  defp helper_parts(helper) do
    cond do
      String.ends_with?(helper, "_path") ->
        {:ok, String.replace_suffix(helper, "_path", ""), :path}

      String.ends_with?(helper, "_url") ->
        {:ok, String.replace_suffix(helper, "_url", ""), :url}

      true ->
        :error
    end
  end

  defp helper_range(meta, helper) do
    with line when is_integer(line) <- Keyword.get(meta, :line),
         column when is_integer(column) <- Keyword.get(meta, :column) do
      {:ok,
       %Range{
         start: %Position{line: line - 1, character: column - 1},
         end: %Position{line: line - 1, character: column - 1 + byte_size(helper)}
       }}
    else
      _missing_position -> :error
    end
  end

  defp route_helper_reference_id(uri, range) do
    "route-helper:#{uri}:#{range.start.line}:#{range.start.character}"
  end

  defp provenance(opts) do
    provenance = %{
      source: :elixir_ast,
      parser: :code_string_to_quoted
    }

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end
end
