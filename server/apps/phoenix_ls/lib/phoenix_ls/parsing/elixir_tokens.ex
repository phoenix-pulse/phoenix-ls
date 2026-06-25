defmodule PhoenixLS.Parsing.ElixirTokens do
  @moduledoc """
  Thin wrapper around Elixir tokenization for source-mapped feature helpers.
  """

  @spec tokenize(String.t()) :: {:ok, [tuple()]} | :error
  def tokenize(source) when is_binary(source) do
    case :elixir_tokenizer.tokenize(String.to_charlist(source), 1, []) do
      {:ok, _line, _column, _warnings, tokens, _comments} -> {:ok, Enum.reverse(tokens)}
      {:error, _reason, _line, _column, _warnings, _tokens} -> :error
    end
  end

  @spec tokenize_prefix(String.t()) :: {:ok, [tuple()]} | :error
  def tokenize_prefix(source) when is_binary(source) do
    case :elixir_tokenizer.tokenize(String.to_charlist(source), 1, []) do
      {:ok, _line, _column, _warnings, tokens, _comments} ->
        {:ok, Enum.reverse(tokens)}

      {:error, _reason, _line, _column, _warnings, tokens} when is_list(tokens) ->
        {:ok, Enum.reverse(tokens)}

      {:error, _reason, _line, _column, tokens} when is_list(tokens) ->
        {:ok, Enum.reverse(tokens)}
    end
  end
end
