defmodule PhoenixLS.Introspection.Template.RenderCall do
  @moduledoc """
  Shared source-only helpers for Phoenix controller template render calls.
  """

  alias PhoenixLS.Support.URI, as: SupportURI

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

  @spec template_argument?([tuple()], non_neg_integer()) :: boolean()
  def template_argument?(tokens, index) do
    with {:ok, open_index} <- enclosing_open_paren(tokens, index),
         true <- render_call_open?(tokens, open_index),
         1 <- top_level_comma_count(tokens, open_index + 1, index - 1) do
      true
    else
      _not_render_template -> false
    end
  end

  @spec candidate_uris(String.t(), String.t(), String.t()) :: [String.t()]
  def candidate_uris(uri, template, format) do
    with {:ok, source_path} <- SupportURI.file_uri_to_path(uri) do
      source_path
      |> candidate_paths(template, format)
      |> Enum.map(&SupportURI.path_to_file_uri!/1)
    else
      _invalid_uri -> []
    end
  end

  defp enclosing_open_paren(tokens, index) do
    find_open_paren(tokens, index - 1, 0)
  end

  defp find_open_paren(_tokens, index, _depth) when index < 0, do: :error

  defp find_open_paren(tokens, index, depth) do
    case Enum.at(tokens, index) |> token_type() do
      :")" ->
        find_open_paren(tokens, index - 1, depth + 1)

      :"(" when depth == 0 ->
        {:ok, index}

      :"(" ->
        find_open_paren(tokens, index - 1, depth - 1)

      _type ->
        find_open_paren(tokens, index - 1, depth)
    end
  end

  defp render_call_open?(tokens, open_index) do
    case Enum.at(tokens, open_index - 1) do
      {:paren_identifier, _meta, name} when name in [:render, :render!] -> true
      _token -> false
    end
  end

  defp top_level_comma_count(_tokens, start_index, end_index) when start_index > end_index,
    do: 0

  defp top_level_comma_count(tokens, start_index, end_index) do
    start_index..end_index
    |> Enum.reduce({0, 0}, fn index, {count, depth} ->
      case Enum.at(tokens, index) |> token_type() do
        type when type in [:"(", :"[", :"{"] ->
          {count, depth + 1}

        type when type in [:")", :"]", :"}"] and depth > 0 ->
          {count, depth - 1}

        :"," when depth == 0 ->
          {count + 1, depth}

        _type ->
          {count, depth}
      end
    end)
    |> elem(0)
  end

  defp token_type({type, _meta}), do: type
  defp token_type({type, _meta, _value}), do: type
  defp token_type(_token), do: nil

  defp candidate_paths(source_path, template, format) do
    controller_dir = Path.dirname(source_path)
    resource = controller_resource(source_path)
    file_name = "#{template}.#{format}.heex"

    [
      Path.join([controller_dir, "#{resource}_html", file_name]),
      Path.join([Path.dirname(controller_dir), "templates", resource, file_name])
    ]
  end

  defp controller_resource(source_path) do
    source_path
    |> Path.basename(".ex")
    |> String.replace_suffix("_controller", "")
  end
end
