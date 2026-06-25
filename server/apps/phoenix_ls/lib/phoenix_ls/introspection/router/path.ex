defmodule PhoenixLS.Introspection.Router.Path do
  @moduledoc """
  Pure path and route helper derivation utilities.
  """

  @spec join(String.t(), String.t()) :: String.t()
  def join("", path), do: normalize(path)
  def join("/", path), do: normalize(path)

  def join(scope_path, path) do
    scope = scope_path |> normalize() |> String.trim_trailing("/")
    route = path |> normalize() |> String.trim_leading("/")

    normalize(scope <> "/" <> route)
  end

  @spec normalize(String.t()) :: String.t()
  def normalize(""), do: "/"
  def normalize("/" <> _rest = path), do: path
  def normalize(path), do: "/" <> path

  @spec helper_base([String.t()], String.t()) :: String.t()
  def helper_base(helper_segments, path) do
    helper_base_from_segments(helper_segments ++ helper_segments_from_path(path))
  end

  @spec helper_base_from_segments([String.t()]) :: String.t()
  def helper_base_from_segments([]), do: "root"

  def helper_base_from_segments(segments) do
    Enum.join(segments, "_")
  end

  @spec helper_prefix([String.t()]) :: String.t() | nil
  def helper_prefix([]), do: nil
  def helper_prefix(segments), do: Enum.join(segments, "_")

  @spec helper_segments_from_path(String.t()) :: [String.t()]
  def helper_segments_from_path(path) do
    path
    |> path_segments()
    |> Enum.reject(&dynamic_path_segment?/1)
    |> Enum.map(&normalize_helper_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&singularize/1)
  end

  @spec helper_segments_from_value(term()) :: [String.t()]
  def helper_segments_from_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> helper_segment_from_value()
  end

  def helper_segments_from_value(value) when is_binary(value) do
    helper_segment_from_value(value)
  end

  def helper_segments_from_value(_value), do: []

  @spec path_params(String.t()) :: [String.t()]
  def path_params(path) do
    path
    |> path_segments()
    |> Enum.filter(&dynamic_path_segment?/1)
    |> Enum.map(&dynamic_param_name/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp helper_segment_from_value(value) do
    value
    |> normalize_helper_segment()
    |> case do
      "" -> []
      segment -> [segment]
    end
  end

  defp path_segments(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end

  defp dynamic_path_segment?(":" <> _name), do: true
  defp dynamic_path_segment?("*" <> _name), do: true
  defp dynamic_path_segment?(_segment), do: false

  defp dynamic_param_name(":" <> name), do: normalize_helper_segment(name)
  defp dynamic_param_name("*" <> name), do: normalize_helper_segment(name)

  defp normalize_helper_segment(segment) do
    segment
    |> String.graphemes()
    |> Enum.map(&helper_grapheme/1)
    |> Enum.reject(&is_nil/1)
    |> collapse_underscores()
    |> trim_underscores()
    |> Enum.join()
  end

  defp helper_grapheme(grapheme) do
    cond do
      grapheme >= "A" and grapheme <= "Z" -> String.downcase(grapheme)
      grapheme >= "a" and grapheme <= "z" -> grapheme
      grapheme >= "0" and grapheme <= "9" -> grapheme
      true -> "_"
    end
  end

  defp collapse_underscores(graphemes) do
    graphemes
    |> Enum.reduce([], fn
      "_", ["_" | _rest] = acc -> acc
      grapheme, acc -> [grapheme | acc]
    end)
    |> Enum.reverse()
  end

  defp trim_underscores(graphemes) do
    graphemes
    |> Enum.drop_while(&(&1 == "_"))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == "_"))
    |> Enum.reverse()
  end

  defp singularize(segment) do
    cond do
      String.ends_with?(segment, "ies") and String.length(segment) > 3 ->
        String.trim_trailing(segment, "ies") <> "y"

      String.ends_with?(segment, "ses") and String.length(segment) > 3 ->
        String.trim_trailing(segment, "es")

      (String.ends_with?(segment, "xes") or String.ends_with?(segment, "zes")) and
          String.length(segment) > 3 ->
        String.trim_trailing(segment, "es")

      String.ends_with?(segment, "s") and not String.ends_with?(segment, "ss") and
          String.length(segment) > 1 ->
        String.trim_trailing(segment, "s")

      true ->
        segment
    end
  end
end
