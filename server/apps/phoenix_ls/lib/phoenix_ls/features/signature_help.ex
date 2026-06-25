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
  alias PhoenixLS.Features.RouteHelpers
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec signature_help(CursorContext.t(), [Fact.t()]) :: SignatureHelp.t() | nil
  def signature_help(%CursorContext{} = context, facts) do
    with tag when is_binary(tag) <- component_tag(context),
         %Fact{} = component <- ComponentLookup.component_for_tag(tag, facts) do
      signature_help_for_component(component, tag, context, facts)
    end
  end

  def signature_help(_context, _facts), do: nil

  @spec signature_help(String.t(), Positions.lsp_position(), [Fact.t()]) ::
          SignatureHelp.t() | nil
  def signature_help(source, position, facts)
      when is_binary(source) and is_map(position) and is_list(facts) do
    with {:ok, helper_name, helper_base, active_parameter} <- RouteHelpers.call(source, position),
         routes when routes != [] <- route_helper_routes(facts, helper_base) do
      route_helper_signature_help(helper_name, routes, active_parameter)
    else
      _not_route_helper -> nil
    end
  end

  defp component_tag(%CursorContext{kind: :tag_name, tag: tag}), do: tag
  defp component_tag(%CursorContext{kind: :attribute_name, tag: tag}), do: tag
  defp component_tag(%CursorContext{kind: :attribute_value, tag: tag}), do: tag
  defp component_tag(_context), do: nil

  defp signature_help_for_component(component, tag, context, facts) do
    attrs = component_attrs(component, facts)
    tag_label = tag_label(tag)

    %SignatureHelp{
      signatures: [signature(component, tag_label, attrs)],
      active_signature: 0,
      active_parameter: active_parameter(attrs, context)
    }
  end

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

  defp active_parameter([], _context), do: nil

  defp active_parameter(attrs, %CursorContext{kind: :attribute_value, attribute: attribute})
       when is_binary(attribute) do
    attrs
    |> Enum.find_index(&(&1.data.name == attribute))
    |> default_active_parameter()
  end

  defp active_parameter(attrs, %CursorContext{prefix: prefix}) do
    active_parameter_for_prefix(attrs, prefix || "")
  end

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

  defp route_helper_routes(facts, helper_base) do
    facts
    |> facts_by_kind(:route)
    |> Enum.filter(&(&1.data.helper_base == helper_base))
    |> Enum.sort_by(&{&1.data.path, action_sort(&1)})
  end

  defp route_helper_signature_help(helper_name, routes, active_parameter) do
    parameter_labels = route_helper_parameter_labels(routes)

    %SignatureHelp{
      signatures: [
        %SignatureInformation{
          label: "Routes.#{helper_name}(#{Enum.join(parameter_labels, ", ")})",
          documentation: route_helper_documentation(helper_name, routes),
          parameters: Enum.map(parameter_labels, &route_helper_parameter/1)
        }
      ],
      active_signature: 0,
      active_parameter: bounded_active_parameter(active_parameter, parameter_labels)
    }
  end

  defp route_helper_parameter_labels(routes) do
    ["conn_or_socket"] ++ action_parameter(routes) ++ path_parameter_labels(routes)
  end

  defp action_parameter(routes) do
    routes
    |> Enum.map(& &1.data.action)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> []
      _actions -> ["action"]
    end
  end

  defp path_parameter_labels(routes) do
    routes
    |> Enum.flat_map(& &1.data.path_params)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp route_helper_parameter(label) do
    %ParameterInformation{
      label: label,
      documentation: route_helper_parameter_documentation(label)
    }
  end

  defp route_helper_parameter_documentation("conn_or_socket") do
    markdown(["Connection or socket passed to the route helper."])
  end

  defp route_helper_parameter_documentation("action") do
    markdown(["Route action atom, such as `:index` or `:show`."])
  end

  defp route_helper_parameter_documentation(label) do
    markdown(["Path parameter `#{label}`."])
  end

  defp route_helper_documentation(helper_name, routes) do
    route_lines =
      routes
      |> Enum.map(fn route ->
        action =
          case route.data.action do
            nil -> ""
            action -> " :" <> Atom.to_string(action)
          end

        "#{verb(route)} #{route.data.path} -> #{route.data.plug}#{action}"
      end)

    markdown(["Route helper `Routes.#{helper_name}`", route_lines])
  end

  defp bounded_active_parameter(active_parameter, parameter_labels) do
    min(active_parameter, length(parameter_labels) - 1)
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

  defp active_parameter_for_prefix(attrs, prefix) do
    attrs
    |> Enum.find_index(&String.starts_with?(&1.data.name, prefix))
    |> default_active_parameter()
  end

  defp default_active_parameter(nil), do: 0
  defp default_active_parameter(index), do: index

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

  defp action_sort(%Fact{data: %{action: nil}}), do: ""
  defp action_sort(%Fact{data: %{action: action}}), do: Atom.to_string(action)

  defp verb(%Fact{data: %{verb: verb}}) when is_atom(verb) do
    verb |> Atom.to_string() |> String.upcase()
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
