defmodule PhoenixLS.Features.SignatureHelp do
  @moduledoc """
  Signature help for Phoenix component calls.
  """

  alias GenLSP.Enumerations.MarkupKind

  alias GenLSP.Structures.{
    MarkupContent,
    ParameterInformation,
    SignatureHelp,
    SignatureInformation
  }

  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec signature_help(CursorContext.t(), [Fact.t()]) :: SignatureHelp.t() | nil
  def signature_help(%CursorContext{kind: :attribute_name, tag: tag, prefix: prefix}, facts) do
    with %Fact{} = component <- ComponentLookup.component_for_tag(tag, facts) do
      attrs = component_attrs(component, facts)
      tag_label = tag_label(tag)

      %SignatureHelp{
        signatures: [signature(component, tag_label, attrs)],
        active_signature: 0,
        active_parameter: active_parameter(attrs, prefix)
      }
    end
  end

  def signature_help(_context, _facts), do: nil

  defp component_attrs(component, facts) do
    facts
    |> facts_by_kind(:component_attr)
    |> Enum.filter(&(&1.data.component == component.id))
    |> Enum.with_index()
    |> Enum.sort_by(fn {fact, index} -> {not required?(fact), index} end)
    |> Enum.map(fn {fact, _index} -> fact end)
  end

  defp signature(component, tag_label, attrs) do
    %SignatureInformation{
      label: signature_label(tag_label, attrs),
      documentation: component_documentation(component),
      parameters: Enum.map(attrs, &parameter_information/1)
    }
  end

  defp signature_label(tag_label, []), do: "<#{tag_label}>"

  defp signature_label(tag_label, attrs) do
    attr_names = Enum.map_join(attrs, " ", & &1.data.name)
    "<#{tag_label} #{attr_names}>"
  end

  defp tag_label(tag) when is_binary(tag), do: tag

  defp component_documentation(component) do
    markdown([
      "Component `#{component.id}`",
      component.data.doc
    ])
  end

  defp parameter_information(attr) do
    %ParameterInformation{
      label: attr.data.name,
      documentation: attr_documentation(attr)
    }
  end

  defp attr_documentation(attr) do
    options = attr.data.options || []

    markdown([
      if(required?(attr), do: "Required", else: "Optional"),
      "Type: `#{inspect(attr.data.type)}`",
      option_line(options, :default, "default"),
      option_line(options, :values, "values"),
      Keyword.get(options, :doc)
    ])
  end

  defp option_line(options, key, label) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> "#{label}: `#{inspect(value)}`"
      :error -> nil
    end
  end

  defp active_parameter([], _prefix), do: nil

  defp active_parameter(attrs, prefix) do
    prefix = prefix || ""

    attrs
    |> Enum.find_index(&String.starts_with?(&1.data.name, prefix))
    |> case do
      nil -> 0
      index -> index
    end
  end

  defp required?(attr), do: Keyword.get(attr.data.options || [], :required, false) == true

  defp markdown(values) do
    %MarkupContent{
      kind: MarkupKind.markdown(),
      value:
        values
        |> List.flatten()
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n\n")
    }
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
