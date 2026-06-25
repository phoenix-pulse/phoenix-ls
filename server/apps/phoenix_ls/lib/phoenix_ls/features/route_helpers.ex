defmodule PhoenixLS.Features.RouteHelpers do
  @moduledoc """
  Token-based helpers for Phoenix `Routes.*_path` and `Routes.*_url` calls.
  """

  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Features.Facts

  @spec prefix(String.t(), Positions.lsp_position()) :: {:ok, String.t()} | :error
  def prefix(source, position) when is_binary(source) and is_map(position) do
    with {:ok, tokens} <- tokens_before(source, position) do
      prefix_from_tokens(tokens)
    end
  end

  @spec call(String.t(), Positions.lsp_position()) ::
          {:ok, String.t(), String.t(), non_neg_integer()} | :error
  def call(source, position) when is_binary(source) and is_map(position) do
    with {:ok, tokens} <- tokens_before(source, position) do
      call_from_tokens(tokens)
    end
  end

  @spec helper_base(String.t()) :: {:ok, String.t()} | :error
  def helper_base(helper_name) when is_binary(helper_name) do
    with {:ok, helper_base, _variant} <- helper_parts(helper_name) do
      {:ok, helper_base}
    end
  end

  @spec helper_parts(String.t()) :: {:ok, String.t(), :path | :url} | :error
  def helper_parts(helper_name) when is_binary(helper_name) do
    cond do
      String.ends_with?(helper_name, "_path") ->
        {:ok, String.replace_suffix(helper_name, "_path", ""), :path}

      String.ends_with?(helper_name, "_url") ->
        {:ok, String.replace_suffix(helper_name, "_url", ""), :url}

      true ->
        :error
    end
  end

  @spec helper_name(String.t(), :path | :url) :: String.t()
  def helper_name(helper_base, variant)
      when is_binary(helper_base) and variant in [:path, :url] do
    "#{helper_base}_#{variant}"
  end

  @spec routes_for_base([Fact.t()], String.t()) :: [Fact.t()]
  def routes_for_base(facts, helper_base) when is_list(facts) and is_binary(helper_base) do
    facts
    |> Facts.by_kind(:route)
    |> Enum.filter(&(&1.data.helper_base == helper_base))
  end

  @spec routes_for_reference(Fact.t(), [Fact.t()]) :: [Fact.t()]
  def routes_for_reference(%Fact{data: %{helper_base: helper_base}}, facts) do
    routes_for_base(facts, helper_base)
  end

  @spec actions([Fact.t()]) :: [String.t()]
  def actions(routes) when is_list(routes) do
    routes
    |> Enum.map(& &1.data.action)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Atom.to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec invalid_action?(Fact.t(), [Fact.t()]) :: boolean()
  def invalid_action?(%Fact{data: %{action: action}}, routes) when is_atom(action) do
    not Enum.any?(routes, &(&1.data.action == action))
  end

  def invalid_action?(_reference, _routes), do: false

  @spec arity_mismatch?(Fact.t(), [Fact.t()]) :: boolean()
  def arity_mismatch?(%Fact{data: %{arity: actual_arity}} = reference, routes)
      when is_integer(actual_arity) do
    expected_arities = expected_arities(reference, routes)

    expected_arities != [] and actual_arity not in expected_arities
  end

  def arity_mismatch?(_reference, _routes), do: false

  @spec expected_arities(Fact.t(), [Fact.t()]) :: [non_neg_integer()]
  def expected_arities(%Fact{data: %{action: action}}, routes) when is_atom(action) do
    routes
    |> Enum.filter(&(&1.data.action == action))
    |> expected_arities()
  end

  def expected_arities(_reference, routes), do: expected_arities(routes)

  @spec expected_arities([Fact.t()]) :: [non_neg_integer()]
  def expected_arities(routes) when is_list(routes) do
    routes
    |> Enum.map(&expected_arity/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec expected_arity(Fact.t()) :: non_neg_integer()
  def expected_arity(%Fact{data: %{action: action, path_params: path_params}}) do
    1 + action_arity(action) + length(path_params)
  end

  @spec action_arity(atom() | nil) :: 0 | 1
  def action_arity(nil), do: 0
  def action_arity(_action), do: 1

  @spec action_parameter_labels([Fact.t()]) :: [String.t()]
  def action_parameter_labels(routes) when is_list(routes) do
    case actions(routes) do
      [] -> []
      _actions -> ["action"]
    end
  end

  @spec path_parameter_labels([Fact.t()]) :: [String.t()]
  def path_parameter_labels(routes) when is_list(routes) do
    routes
    |> Enum.flat_map(& &1.data.path_params)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec action_sort(Fact.t()) :: String.t()
  def action_sort(%Fact{data: %{action: nil}}), do: ""
  def action_sort(%Fact{data: %{action: action}}), do: Atom.to_string(action)

  @spec verb(Fact.t()) :: String.t()
  def verb(%Fact{data: %{verb: verb}}) when is_atom(verb) do
    verb |> Atom.to_string() |> String.upcase()
  end

  defp tokens_before(source, position) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, source_before_cursor} <- source_before_cursor(source, offset) do
      tokenize(source_before_cursor)
    end
  end

  defp source_before_cursor(source, offset) when offset <= byte_size(source) do
    {:ok, binary_part(source, 0, offset)}
  end

  defp source_before_cursor(_source, _offset), do: :error

  defp tokenize(source) do
    case :elixir_tokenizer.tokenize(String.to_charlist(source), 1, []) do
      {:ok, _line, _column, _warnings, tokens, _comments} ->
        {:ok, tokens}

      {:error, _reason, _warnings, _rest, tokens} when is_list(tokens) ->
        {:ok, tokens}

      {:error, _reason, _line, _column, _warnings, tokens} when is_list(tokens) ->
        {:ok, tokens}

      _unexpected ->
        :error
    end
  end

  defp prefix_from_tokens([
         {:identifier, _identifier_meta, helper_prefix},
         {:., _dot_meta},
         {:alias, _alias_meta, :Routes}
         | _rest
       ]) do
    {:ok, Atom.to_string(helper_prefix)}
  end

  defp prefix_from_tokens([
         {:., _dot_meta},
         {:alias, _alias_meta, :Routes}
         | _rest
       ]) do
    {:ok, ""}
  end

  defp prefix_from_tokens(_tokens), do: :error

  defp call_from_tokens(tokens) do
    find_call(tokens, 0, 0)
  end

  defp find_call([], _depth, _comma_count), do: :error

  defp find_call([{:",", _meta} | rest], 0, comma_count) do
    find_call(rest, 0, comma_count + 1)
  end

  defp find_call([{:"(", _meta} | rest], 0, comma_count) do
    call_after_open(rest, comma_count)
  end

  defp find_call([token | rest], depth, comma_count) do
    case token_kind(token) do
      kind when kind in [:")", :"]", :"}"] ->
        find_call(rest, depth + 1, comma_count)

      kind when kind in [:"(", :"[", :"{"] and depth > 0 ->
        find_call(rest, depth - 1, comma_count)

      _other ->
        find_call(rest, depth, comma_count)
    end
  end

  defp call_after_open(
         [
           {:paren_identifier, _helper_meta, helper},
           {:., _dot_meta},
           {:alias, _alias_meta, :Routes}
           | _rest
         ],
         comma_count
       )
       when is_atom(helper) do
    helper_name = Atom.to_string(helper)

    with {:ok, helper_base} <- helper_base(helper_name) do
      {:ok, helper_name, helper_base, comma_count}
    end
  end

  defp call_after_open(_tokens, _comma_count), do: :error

  defp token_kind({kind, _meta}), do: kind
  defp token_kind({kind, _meta, _value}), do: kind
  defp token_kind(_token), do: nil
end
