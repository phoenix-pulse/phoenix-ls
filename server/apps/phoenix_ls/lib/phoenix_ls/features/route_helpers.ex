defmodule PhoenixLS.Features.RouteHelpers do
  @moduledoc """
  Token-based helpers for Phoenix `Routes.*_path` and `Routes.*_url` calls.
  """

  alias PhoenixLS.Support.Positions

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
    cond do
      String.ends_with?(helper_name, "_path") ->
        {:ok, String.trim_trailing(helper_name, "_path")}

      String.ends_with?(helper_name, "_url") ->
        {:ok, String.trim_trailing(helper_name, "_url")}

      true ->
        :error
    end
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
