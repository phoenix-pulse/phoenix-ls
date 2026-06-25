defmodule PhoenixLS.Introspection.Source do
  @moduledoc """
  Shared source metadata helpers for source-only introspection modules.
  """

  alias GenLSP.Structures.{Position, Range}

  @spec top_level_expressions(term()) :: [term()]
  def top_level_expressions({:__block__, _meta, expressions}), do: expressions
  def top_level_expressions(nil), do: []
  def top_level_expressions(expression), do: [expression]

  @spec alias_to_string(term()) :: {:ok, String.t()} | :error
  def alias_to_string({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1) do
      {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
    else
      :error
    end
  end

  def alias_to_string(atom) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  def alias_to_string(_ast), do: :error

  @spec static_literal(term()) :: {:ok, term()} | :error
  def static_literal(value)
      when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value),
      do: {:ok, value}

  def static_literal(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, literals} ->
      case static_literal(value) do
        {:ok, literal} -> {:cont, {:ok, [literal | literals]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, literals} -> {:ok, Enum.reverse(literals)}
      :error -> :error
    end
  end

  def static_literal({sigil, _meta, [{:<<>>, _string_meta, [words]}, modifiers]})
      when is_binary(words) and is_list(modifiers) do
    if sigil in [:sigil_w, :sigil_W] and modifiers == [] do
      {:ok, String.split(words)}
    else
      :error
    end
  end

  def static_literal(_value), do: :error

  @spec source_range(keyword()) :: Range.t()
  def source_range(meta) do
    %Range{
      start: position(meta),
      end: end_meta(meta) |> position()
    }
  end

  @spec position(keyword()) :: Position.t()
  def position(meta) do
    %Position{
      line: meta |> Keyword.get(:line, 1) |> zero_based(),
      character: meta |> Keyword.get(:column, 1) |> zero_based()
    }
  end

  @spec zero_based(term()) :: non_neg_integer()
  def zero_based(value) when is_integer(value) and value > 0, do: value - 1
  def zero_based(_value), do: 0

  defp end_meta(meta) do
    Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end) || meta
  end
end
