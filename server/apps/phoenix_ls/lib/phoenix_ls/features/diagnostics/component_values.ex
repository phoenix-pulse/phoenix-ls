defmodule PhoenixLS.Features.Diagnostics.ComponentValues do
  @moduledoc """
  Diagnostics for static component attr values declared with finite `:values`.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}

  @spec diagnostics(Tag.t(), [PhoenixLS.Index.Fact.t()]) :: [
          GenLSP.Structures.Diagnostic.t()
        ]
  def diagnostics(%Tag{} = tag, attrs) when is_list(attrs) do
    attrs
    |> Enum.flat_map(fn fact ->
      case {Keyword.get(fact.data.options || [], :values), find_attr(tag, fact.data.name)} do
        {values, %Attribute{} = attr} when is_list(values) ->
          validate_attr_value(tag, attr, values)

        _other ->
          []
      end
    end)
  end

  defp validate_attr_value(
         %Tag{} = tag,
         %Attribute{value: value, value_kind: kind} = attr,
         values
       )
       when kind in [:quoted, :unquoted] and is_binary(value) do
    allowed_values = MapSet.new(values, &value_to_string/1)
    value_strings = Enum.map(values, &value_to_string/1)

    if MapSet.member?(allowed_values, value) do
      []
    else
      [invalid_attr_value_diagnostic(tag, attr, value, value_strings)]
    end
  end

  defp validate_attr_value(
         %Tag{} = tag,
         %Attribute{value: value, value_kind: :expression} = attr,
         values
       )
       when is_binary(value) do
    with {:ok, literal_value} <- literal_expression_value(value) do
      allowed_values = MapSet.new(values, &value_to_string/1)
      value_string = value_to_string(literal_value)

      if MapSet.member?(allowed_values, value_string) do
        []
      else
        [
          invalid_attr_value_diagnostic(
            tag,
            attr,
            value_string,
            Enum.map(values, &value_to_string/1),
            Enum.map(values, &expression_literal_source/1)
          )
        ]
      end
    else
      _dynamic_expression -> []
    end
  end

  defp validate_attr_value(_tag, _attr, _values), do: []

  defp invalid_attr_value_diagnostic(tag, attr, value, values, replacement_values \\ nil) do
    data =
      %{
        "kind" => "invalid_attr_value",
        "tag" => tag.name,
        "attr" => attr.name,
        "value" => value,
        "values" => values
      }
      |> maybe_put("replacementValues", replacement_values)

    Builder.diagnostic(
      attr.value_range || attr.name_range,
      "phoenix.invalid_attr_value",
      ~s(Invalid value "#{value}" for #{tag.name} #{attr.name}),
      data
    )
  end

  defp literal_expression_value(value) do
    case Code.string_to_quoted(value) do
      {:ok, literal} when is_atom(literal) or is_binary(literal) or is_number(literal) ->
        {:ok, literal}

      _dynamic_or_invalid ->
        :error
    end
  end

  defp find_attr(%Tag{attrs: attrs}, name) do
    Enum.find(attrs, &(&1.name == name))
  end

  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_to_string(value), do: inspect(value)

  defp expression_literal_source(true), do: "true"
  defp expression_literal_source(false), do: "false"
  defp expression_literal_source(nil), do: "nil"
  defp expression_literal_source(value) when is_atom(value), do: ":" <> Atom.to_string(value)
  defp expression_literal_source(value), do: inspect(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
