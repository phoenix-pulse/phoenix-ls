defmodule PhoenixLS.Features.Diagnostics.PhoenixAttrs do
  @moduledoc """
  Diagnostics for `phx-*` attribute names and constrained values.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.Features.Completion.SpecialAttrs
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.LiveView.Attributes
  alias PhoenixLS.LiveView.JSCommands

  @spec diagnostics(Tag.t()) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Tag{} = tag) do
    phx_attr_name_diagnostics(tag) ++
      phx_attr_value_diagnostics(tag) ++
      live_view_js_option_diagnostics(tag)
  end

  defp phx_attr_name_diagnostics(%Tag{} = tag) do
    tag.attrs
    |> Enum.filter(&phx_attr?/1)
    |> Enum.reject(&known_phx_attr?/1)
    |> Enum.map(fn attr ->
      Builder.diagnostic(
        attr.name_range,
        "phoenix.unknown_phx_attr",
        ~s(Unknown Phoenix attr "#{attr.name}"),
        %{
          "kind" => "unknown_phx_attr",
          "tag" => tag.name,
          "attr" => attr.name
        }
      )
    end)
  end

  defp phx_attr_value_diagnostics(%Tag{} = tag) do
    tag.attrs
    |> Enum.flat_map(fn attr ->
      case Attributes.value_set(attr.name) do
        {:ok, values} -> validate_phx_attr_value(attr, values)
        :error -> []
      end
    end)
  end

  defp validate_phx_attr_value(%Attribute{value: value} = attr, values)
       when is_binary(value) do
    allowed_values = MapSet.new(values)

    if literal_attr_value?(attr) and value != "" and
         not MapSet.member?(allowed_values, value) do
      [
        Builder.diagnostic(
          attr.value_range || attr.name_range,
          "phoenix.invalid_phx_attr_value",
          ~s(Invalid value "#{value}" for #{attr.name}),
          %{
            "kind" => "invalid_phx_attr_value",
            "attr" => attr.name,
            "value" => value,
            "values" => values
          }
        )
      ]
    else
      []
    end
  end

  defp validate_phx_attr_value(_attr, _values), do: []

  defp live_view_js_option_diagnostics(%Tag{} = tag) do
    tag.attrs
    |> Enum.filter(&phx_attr?/1)
    |> Enum.flat_map(&live_view_js_option_diagnostics_for_attr/1)
  end

  defp live_view_js_option_diagnostics_for_attr(
         %Attribute{
           value: value,
           value_kind: :expression
         } = attr
       )
       when is_binary(value) do
    with {:ok, ast} <- Code.string_to_quoted(value, columns: true, token_metadata: true) do
      ast
      |> JSCommands.invalid_options()
      |> Enum.map(&invalid_live_view_js_option_diagnostic(attr, &1))
    else
      _dynamic_or_incomplete -> []
    end
  end

  defp live_view_js_option_diagnostics_for_attr(_attr), do: []

  defp invalid_live_view_js_option_diagnostic(attr, invalid) do
    Builder.diagnostic(
      attr.value_range || attr.name_range,
      "phoenix.invalid_live_view_js_option",
      "Unknown JS.#{invalid.command} option :#{invalid.option}",
      %{
        "kind" => "invalid_live_view_js_option",
        "command" => invalid.command,
        "option" => invalid.option,
        "knownOptions" => invalid.known_options
      }
    )
  end

  defp phx_attr?(%Attribute{name: "phx-" <> _suffix}), do: true
  defp phx_attr?(_attr), do: false

  defp known_phx_attr?(%Attribute{name: name}) do
    Attributes.known_attr?(name) or SpecialAttrs.known?(name)
  end

  defp literal_attr_value?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_attr_value?(_attr), do: false
end
