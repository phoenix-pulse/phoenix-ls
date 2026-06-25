defmodule PhoenixLS.Features.Diagnostics do
  @moduledoc """
  Phoenix diagnostics derived from parsed HEEx documents and indexed facts.
  """

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact

  @source "PhoenixLS"
  @live_component_required_attrs ["id", "module"]
  @global_component_attrs ["id", "class", "style", "title"]
  @global_slot_attrs [":let"]
  @non_event_phx_attrs ["phx-target", "phx-disable-with"]
  @global_prefix_attrs ["aria-", "data-"]

  @spec diagnostics(Document.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(%Document{tags: tags}, facts) when is_list(facts) do
    indexes = indexes(facts)

    tags
    |> Enum.flat_map(&tag_diagnostics(&1, indexes))
  end

  @spec diagnostics(String.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    template_uris =
      facts
      |> facts_by_kind(:template)
      |> MapSet.new(& &1.uri)

    facts
    |> facts_by_kind(:template_reference)
    |> Enum.filter(&(&1.uri == uri))
    |> Enum.reject(&known_template_reference?(&1, template_uris))
    |> Enum.map(&unknown_template_diagnostic/1)
  end

  defp tag_diagnostics(%Tag{kind: :component, name: ".live_component"} = tag, indexes) do
    live_component_diagnostics(tag) ++
      route_diagnostics(tag, indexes) ++ event_diagnostics(tag, indexes)
  end

  defp tag_diagnostics(%Tag{kind: kind} = tag, indexes)
       when kind in [:component, :remote_component] do
    component_diagnostics =
      case ComponentLookup.component_for_tag(tag.name, indexes.facts) do
        %Fact{} = component -> known_component_diagnostics(tag, component, indexes)
        nil -> []
      end

    component_diagnostics ++ route_diagnostics(tag, indexes) ++ event_diagnostics(tag, indexes)
  end

  defp tag_diagnostics(%Tag{kind: :slot} = tag, indexes) do
    slot_name = trim_leading(tag.name, ":")

    diagnostics =
      if MapSet.member?(indexes.slots, slot_name) do
        known_slot_diagnostics(tag, slot_name, indexes)
      else
        [
          diagnostic(
            tag.name_range,
            "phoenix.unknown_slot",
            ~s(Unknown slot "#{tag.name}")
          )
        ]
      end

    diagnostics ++ route_diagnostics(tag, indexes) ++ event_diagnostics(tag, indexes)
  end

  defp tag_diagnostics(%Tag{} = tag, indexes) do
    route_diagnostics(tag, indexes) ++ event_diagnostics(tag, indexes)
  end

  defp known_component_diagnostics(%Tag{} = tag, %Fact{} = component, indexes) do
    attrs = Map.get(indexes.attrs_by_component, component.id, [])
    declared_attr_names = MapSet.new(attrs, & &1.data.name)
    present_attr_names = MapSet.new(tag.attrs, & &1.name)

    missing_required_attr_diagnostics(tag, attrs, present_attr_names) ++
      unknown_attr_diagnostics(tag, declared_attr_names) ++
      invalid_value_diagnostics(tag, attrs)
  end

  defp known_slot_diagnostics(%Tag{} = tag, slot_name, indexes) do
    attrs = Map.get(indexes.attrs_by_slot, slot_name, [])
    declared_attr_names = MapSet.new(attrs, & &1.data.name)

    unknown_slot_attr_diagnostics(tag, declared_attr_names) ++
      invalid_value_diagnostics(tag, attrs)
  end

  defp missing_required_attr_diagnostics(%Tag{} = tag, attrs, present_attr_names) do
    attrs
    |> Enum.filter(&required_attr?/1)
    |> Enum.reject(&MapSet.member?(present_attr_names, &1.data.name))
    |> Enum.map(fn attr ->
      diagnostic(
        tag.name_range,
        "phoenix.missing_required_attr",
        ~s(Missing required attr "#{attr.data.name}" for #{tag.name}),
        %{
          "kind" => "missing_required_attr",
          "tag" => tag.name,
          "attr" => attr.data.name
        }
      )
    end)
  end

  defp unknown_attr_diagnostics(%Tag{} = tag, declared_attr_names) do
    tag.attrs
    |> Enum.reject(&MapSet.member?(declared_attr_names, &1.name))
    |> Enum.reject(&global_component_attr?/1)
    |> Enum.map(fn attr ->
      diagnostic(
        attr.name_range,
        "phoenix.unknown_attr",
        ~s(Unknown attr "#{attr.name}" for #{tag.name})
      )
    end)
  end

  defp unknown_slot_attr_diagnostics(%Tag{} = tag, declared_attr_names) do
    tag.attrs
    |> Enum.reject(&MapSet.member?(declared_attr_names, &1.name))
    |> Enum.reject(&global_slot_attr?/1)
    |> Enum.reject(&global_component_attr?/1)
    |> Enum.map(fn attr ->
      diagnostic(
        attr.name_range,
        "phoenix.unknown_attr",
        ~s(Unknown attr "#{attr.name}" for #{tag.name})
      )
    end)
  end

  defp invalid_value_diagnostics(%Tag{} = tag, attrs) do
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
      [
        diagnostic(
          attr.value_range || attr.name_range,
          "phoenix.invalid_attr_value",
          ~s(Invalid value "#{value}" for #{tag.name} #{attr.name}),
          %{
            "kind" => "invalid_attr_value",
            "tag" => tag.name,
            "attr" => attr.name,
            "value" => value,
            "values" => value_strings
          }
        )
      ]
    end
  end

  defp validate_attr_value(_tag, _attr, _values), do: []

  defp live_component_diagnostics(%Tag{} = tag) do
    present_attr_names = MapSet.new(tag.attrs, & &1.name)

    @live_component_required_attrs
    |> Enum.reject(&MapSet.member?(present_attr_names, &1))
    |> Enum.map(fn attr_name ->
      diagnostic(
        tag.name_range,
        "phoenix.missing_live_component_attr",
        ~s(Missing required attr "#{attr_name}" for .live_component)
      )
    end)
  end

  defp route_diagnostics(%Tag{} = tag, indexes) do
    tag.attrs
    |> Enum.flat_map(fn attr ->
      case verified_route_path(attr) do
        {:ok, path} ->
          if MapSet.member?(indexes.routes, path) do
            []
          else
            [
              diagnostic(
                attr.value_range || attr.name_range,
                "phoenix.unknown_route",
                ~s(Unknown verified route "#{path}")
              )
            ]
          end

        :error ->
          []
      end
    end)
  end

  defp event_diagnostics(%Tag{} = tag, indexes) do
    tag.attrs
    |> Enum.filter(&event_attr?/1)
    |> Enum.reject(&blank?(&1.value))
    |> Enum.reject(&MapSet.member?(indexes.events, &1.value))
    |> Enum.map(fn attr ->
      diagnostic(
        attr.value_range || attr.name_range,
        "phoenix.unknown_event",
        ~s(Unknown LiveView event "#{attr.value}")
      )
    end)
  end

  defp known_template_reference?(%Fact{data: %{candidate_uris: candidate_uris}}, template_uris) do
    Enum.any?(candidate_uris, &MapSet.member?(template_uris, &1))
  end

  defp unknown_template_diagnostic(%Fact{range: range, data: data}) do
    diagnostic(
      range,
      "phoenix.unknown_template",
      ~s(Unknown template "#{data.template}.#{data.format}.heex")
    )
  end

  defp verified_route_path(%Attribute{value: value}) when is_binary(value) do
    cond do
      String.starts_with?(value, "~p\"") and String.ends_with?(value, "\"") ->
        {:ok, value |> trim_leading("~p\"") |> trim_trailing("\"")}

      String.starts_with?(value, "~p'") and String.ends_with?(value, "'") ->
        {:ok, value |> trim_leading("~p'") |> trim_trailing("'")}

      true ->
        :error
    end
  end

  defp verified_route_path(_attr), do: :error

  defp event_attr?(%Attribute{name: name}) do
    String.starts_with?(name, "phx-") and
      name not in @non_event_phx_attrs and
      not String.starts_with?(name, "phx-value-")
  end

  defp global_component_attr?(%Attribute{name: name}) do
    name in @global_component_attrs or
      String.starts_with?(name, @global_prefix_attrs) or
      String.starts_with?(name, "phx-")
  end

  defp global_slot_attr?(%Attribute{name: name}) do
    name in @global_slot_attrs
  end

  defp required_attr?(%Fact{data: %{options: options}}) do
    Keyword.get(options || [], :required, false) == true
  end

  defp find_attr(%Tag{attrs: attrs}, name) do
    Enum.find(attrs, &(&1.name == name))
  end

  defp indexes(facts) do
    %{
      facts: facts,
      attrs_by_component:
        facts
        |> facts_by_kind(:component_attr)
        |> Enum.group_by(& &1.data.component),
      attrs_by_slot:
        facts
        |> facts_by_kind(:component_slot_attr)
        |> Enum.group_by(& &1.data.slot),
      slots:
        facts
        |> facts_by_kind(:component_slot)
        |> MapSet.new(& &1.data.name),
      events:
        facts
        |> facts_by_kind(:live_event)
        |> MapSet.new(& &1.data.event),
      routes:
        facts
        |> facts_by_kind(:route)
        |> MapSet.new(& &1.data.path)
    }
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end

  defp diagnostic(range, code, message, data \\ nil) do
    %Diagnostic{
      range: range,
      severity: DiagnosticSeverity.error(),
      code: code,
      source: @source,
      message: message,
      data: data
    }
  end

  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_to_string(value), do: inspect(value)

  defp trim_leading(value, prefix), do: String.trim_leading(value, prefix)
  defp trim_trailing(value, suffix), do: String.trim_trailing(value, suffix)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
