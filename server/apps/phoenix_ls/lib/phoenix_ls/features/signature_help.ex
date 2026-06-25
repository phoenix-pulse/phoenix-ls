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

  alias PhoenixLS.Features.{ComponentDocs, ComponentLookup}
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Features.RouteHelpers
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.JSCommands
  alias PhoenixLS.Support.Positions

  @spec signature_help(CursorContext.t(), [Fact.t()]) :: SignatureHelp.t() | nil
  def signature_help(%CursorContext{} = context, facts) do
    with tag when is_binary(tag) <- component_tag(context),
         %Fact{} = fact <- component_or_slot_for_tag(tag, facts) do
      signature_help_for_fact(fact, tag, context, facts)
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
      _not_route_helper ->
        js_signature_help(source, position) || component_signature_help(source, position, facts)
    end
  end

  defp component_tag(%CursorContext{kind: :tag_name, tag: tag}), do: tag
  defp component_tag(%CursorContext{kind: :attribute_name, tag: tag}), do: tag
  defp component_tag(%CursorContext{kind: :attribute_value, tag: tag}), do: tag
  defp component_tag(_context), do: nil

  defp component_or_slot_for_tag(tag, facts) do
    ComponentLookup.component_for_tag(tag, facts) ||
      ComponentLookup.slot_for_tag(tag, facts)
  end

  defp component_or_slot_for_source_tag(":" <> _ = tag, source, position, facts) do
    ComponentLookup.slot_for_source_tag(tag, source, position, facts)
  end

  defp component_or_slot_for_source_tag(tag, _source, _position, facts) do
    ComponentLookup.component_for_tag(tag, facts)
  end

  defp signature_help_for_fact(%Fact{kind: :component} = component, tag, context, facts) do
    signature_help_for_component(component, tag, context, facts)
  end

  defp signature_help_for_fact(%Fact{kind: :component_slot} = slot, tag, context, facts) do
    signature_help_for_slot(slot, tag, context, facts)
  end

  defp signature_help_for_component(component, tag, context, facts) do
    attrs = component_attrs(component, facts)
    tag_label = tag_label(tag)

    %SignatureHelp{
      signatures: [signature(component, tag_label, attrs, facts)],
      active_signature: 0,
      active_parameter: active_parameter(attrs, context)
    }
  end

  defp signature_help_for_slot(slot, tag, context, facts) do
    attrs = slot_attrs(slot, facts)
    tag_label = tag_label(tag)

    %SignatureHelp{
      signatures: [slot_signature(slot, tag_label, attrs, facts)],
      active_signature: 0,
      active_parameter: active_parameter(attrs, context)
    }
  end

  defp component_signature_help(source, position, facts) do
    with {:ok, context} <- CursorContext.at(source, position),
         tag when is_binary(tag) <- component_tag(context),
         %Fact{} = fact <- component_or_slot_for_source_tag(tag, source, position, facts) do
      signature_help_for_fact(fact, tag, context, facts)
    else
      _not_component_context -> nil
    end
  end

  defp js_signature_help(source, position) do
    with {:ok, %CursorContext{kind: :expression, attribute: "phx-" <> _, prefix: prefix}} <-
           CursorContext.at(source, position),
         command when not is_nil(command) <- JSCommands.command_for_prefix(prefix) do
      js_command_signature_help(command, prefix)
    else
      _not_js_context -> nil
    end
  end

  defp component_attrs(component, facts) do
    facts
    |> Facts.by_kind(:component_attr)
    |> Enum.filter(&(&1.data.component == component.id))
    |> Enum.with_index()
    |> Enum.sort_by(fn {fact, index} -> {not required?(fact), index} end)
    |> Enum.map(fn {fact, _index} -> fact end)
  end

  defp slot_attrs(slot, facts) do
    facts
    |> Facts.by_kind(:component_slot_attr)
    |> Enum.filter(&(&1.data.component == slot.data.component and &1.data.slot == slot.data.name))
    |> Enum.with_index()
    |> Enum.sort_by(fn {fact, index} -> {not required?(fact), index} end)
    |> Enum.map(fn {fact, _index} -> fact end)
  end

  defp signature(component, tag_label, attrs, facts) do
    %SignatureInformation{
      label: signature_label(tag_label, attrs),
      documentation: component_documentation(component, facts),
      parameters: Enum.map(attrs, &parameter_information/1)
    }
  end

  defp slot_signature(slot, tag_label, attrs, facts) do
    %SignatureInformation{
      label: signature_label(tag_label, attrs),
      documentation: slot_documentation(slot, facts),
      parameters: Enum.map(attrs, &slot_parameter_information/1)
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

  defp component_documentation(component, facts) do
    component
    |> ComponentDocs.component_markdown(facts)
    |> markdown()
  end

  defp slot_documentation(slot, facts) do
    slot
    |> ComponentDocs.slot_markdown(facts)
    |> markdown()
  end

  defp parameter_information(attr) do
    %ParameterInformation{
      label: attr.data.name,
      documentation: attr |> ComponentDocs.attr_markdown() |> markdown()
    }
  end

  defp slot_parameter_information(attr) do
    %ParameterInformation{
      label: attr.data.name,
      documentation: attr |> ComponentDocs.slot_attr_markdown() |> markdown()
    }
  end

  defp route_helper_routes(facts, helper_base) do
    facts
    |> RouteHelpers.routes_for_base(helper_base)
    |> Enum.sort_by(&{&1.data.path, RouteHelpers.action_sort(&1)})
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
    ["conn_or_socket"] ++
      RouteHelpers.action_parameter_labels(routes) ++ RouteHelpers.path_parameter_labels(routes)
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

        "#{RouteHelpers.verb(route)} #{route.data.path} -> #{route.data.plug}#{action}"
      end)

    markdown(["Route helper `Routes.#{helper_name}`", route_lines])
  end

  defp js_command_signature_help(command, prefix) do
    parameters = Enum.map(command.options, &js_command_parameter/1)

    %SignatureHelp{
      signatures: [
        %SignatureInformation{
          label: JSCommands.signature_label(command),
          documentation: command |> JSCommands.markdown() |> markdown(),
          parameters: parameters
        }
      ],
      active_signature: 0,
      active_parameter: active_js_parameter(command.options, prefix)
    }
  end

  defp js_command_parameter({label, snippet}) do
    %ParameterInformation{
      label: label,
      documentation: markdown(["JS option `#{label}`", "Snippet: `#{snippet}`"])
    }
  end

  defp active_js_parameter(options, prefix) do
    option_prefix = active_option_prefix(prefix)

    options
    |> Enum.find_index(fn {label, _snippet} -> String.starts_with?(label, option_prefix) end)
    |> default_active_parameter()
  end

  defp active_option_prefix(prefix) do
    prefix
    |> String.split(",")
    |> List.last()
    |> String.trim_leading()
    |> String.split(":", parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp bounded_active_parameter(active_parameter, parameter_labels) do
    min(active_parameter, length(parameter_labels) - 1)
  end

  defp active_parameter_for_prefix(attrs, prefix) do
    attrs
    |> Enum.find_index(&String.starts_with?(&1.data.name, prefix))
    |> default_active_parameter()
  end

  defp default_active_parameter(nil), do: 0
  defp default_active_parameter(index), do: index

  defp required?(attr), do: Keyword.get(attr.data.options || [], :required, false) == true

  defp markdown(value) when is_binary(value) do
    %MarkupContent{
      kind: MarkupKind.markdown(),
      value: value
    }
  end

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

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
