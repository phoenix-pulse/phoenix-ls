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
  @event_phx_attrs [
    "phx-click",
    "phx-submit",
    "phx-change",
    "phx-blur",
    "phx-focus",
    "phx-keydown",
    "phx-keyup",
    "phx-window-keydown",
    "phx-window-keyup",
    "phx-window-focus",
    "phx-window-blur",
    "phx-click-away",
    "phx-capture-click",
    "phx-viewport-top",
    "phx-viewport-bottom",
    "phx-auto-recover"
  ]
  @non_event_phx_attrs [
    "phx-target",
    "phx-disable-with",
    "phx-update",
    "phx-debounce",
    "phx-throttle",
    "phx-hook",
    "phx-mounted",
    "phx-remove",
    "phx-connected",
    "phx-disconnected",
    "phx-trigger-action",
    "phx-feedback-for",
    "phx-track-static",
    "phx-drop-target",
    "phx-no-curly-interpolation",
    "phx-page-loading",
    "phx-link",
    "phx-key"
  ]
  @known_phx_attrs @event_phx_attrs ++ @non_event_phx_attrs
  @dynamic_phx_attr_prefixes ["phx-value-"]
  @global_prefix_attrs ["aria-", "data-"]

  @spec diagnostics(Document.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(%Document{tags: tags}, facts) when is_list(facts) do
    indexes = indexes(facts)

    tags
    |> Enum.flat_map(&tag_diagnostics(&1, indexes, tags))
  end

  @spec diagnostics(String.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    template_uris =
      facts
      |> facts_by_kind(:template)
      |> MapSet.new(& &1.uri)

    template_diagnostics =
      facts
      |> facts_by_kind(:template_reference)
      |> Enum.filter(&(&1.uri == uri))
      |> Enum.reject(&known_template_reference?(&1, template_uris))
      |> Enum.map(&unknown_template_diagnostic/1)

    route_helper_diagnostics =
      facts
      |> facts_by_kind(:route_helper_reference)
      |> Enum.filter(&(&1.uri == uri))
      |> Enum.reject(&known_route_helper_reference?(&1, facts))
      |> Enum.map(&unknown_route_helper_diagnostic/1)

    template_diagnostics ++ route_helper_diagnostics
  end

  defp tag_diagnostics(%Tag{kind: :component, name: ".live_component"} = tag, indexes, tags) do
    live_component_diagnostics(tag) ++
      shared_tag_diagnostics(tag, indexes, tags)
  end

  defp tag_diagnostics(%Tag{kind: kind} = tag, indexes, tags)
       when kind in [:component, :remote_component] do
    component_diagnostics =
      case ComponentLookup.component_for_tag(tag.name, indexes.facts) do
        %Fact{} = component -> known_component_diagnostics(tag, component, indexes)
        nil -> []
      end

    component_diagnostics ++
      shared_tag_diagnostics(tag, indexes, tags)
  end

  defp tag_diagnostics(%Tag{kind: :slot} = tag, indexes, tags) do
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

    diagnostics ++
      shared_tag_diagnostics(tag, indexes, tags)
  end

  defp tag_diagnostics(%Tag{} = tag, indexes, tags) do
    for_tracking_diagnostics(tag) ++
      shared_tag_diagnostics(tag, indexes, tags)
  end

  defp shared_tag_diagnostics(%Tag{} = tag, indexes, tags) do
    phx_attr_name_diagnostics(tag) ++
      route_diagnostics(tag, indexes) ++
      event_diagnostics(tag, indexes) ++
      stream_diagnostics(tag, tags)
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
        ~s(Missing required attr "#{attr_name}" for .live_component),
        %{
          "kind" => "missing_live_component_attr",
          "tag" => ".live_component",
          "attr" => attr_name
        }
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
    |> Enum.filter(&literal_event_attr?/1)
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

  defp phx_attr_name_diagnostics(%Tag{} = tag) do
    tag.attrs
    |> Enum.filter(&phx_attr?/1)
    |> Enum.reject(&known_phx_attr?/1)
    |> Enum.map(fn attr ->
      diagnostic(
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

  defp for_tracking_diagnostics(%Tag{kind: :html} = tag) do
    case find_attr(tag, ":for") do
      %Attribute{} = for_attr ->
        if tracked_for?(tag) or stream_for?(for_attr) do
          []
        else
          item = for_item(for_attr)

          [
            diagnostic(
              for_attr.range,
              "phoenix.for_missing_key",
              ~s(HTML element "#{tag.name}" with :for should have DOM tracking. Add id={#{item}.id} or :key={#{item}.id}.),
              %{
                "kind" => "for_missing_key",
                "tag" => tag.name,
                "item" => item
              },
              DiagnosticSeverity.warning()
            )
          ]
        end

      nil ->
        []
    end
  end

  defp tracked_for?(%Tag{} = tag) do
    match?(%Attribute{}, find_attr(tag, "id")) or match?(%Attribute{}, find_attr(tag, ":key"))
  end

  defp stream_for?(%Attribute{value: value}) when is_binary(value) do
    String.contains?(value, "@streams.")
  end

  defp stream_for?(_attr), do: false

  defp stream_diagnostics(%Tag{} = tag, tags) do
    case find_attr(tag, ":for") do
      %Attribute{} = for_attr ->
        case stream_info(for_attr) do
          {:ok, stream} -> valid_stream_diagnostics(tag, tags, stream)
          {:invalid_pattern, stream} -> invalid_stream_pattern_diagnostic(for_attr, stream)
          :not_stream -> []
        end

      nil ->
        []
    end
  end

  defp valid_stream_diagnostics(%Tag{} = tag, tags, stream) do
    missing_stream_id_diagnostics(tag, stream) ++
      unnecessary_stream_key_diagnostics(tag, stream) ++
      missing_stream_update_diagnostics(tag, tags, stream)
  end

  defp invalid_stream_pattern_diagnostic(%Attribute{} = for_attr, stream) do
    [
      diagnostic(
        for_attr.range,
        "phoenix.stream_invalid_pattern",
        "Stream iteration must destructure tuple: use `{dom_id, #{stream.item}} <- @streams.#{stream.name}`.",
        %{
          "kind" => "stream_invalid_pattern",
          "stream" => stream.name,
          "item" => stream.item
        }
      )
    ]
  end

  defp missing_stream_id_diagnostics(%Tag{} = tag, stream) do
    if stream_id_attr?(tag, stream.dom_id) do
      []
    else
      [
        diagnostic(
          tag.name_range,
          "phoenix.stream_missing_id",
          "Stream item must have `id={#{stream.dom_id}}` for LiveView DOM tracking.",
          %{
            "kind" => "stream_missing_id",
            "stream" => stream.name,
            "dom_id" => stream.dom_id
          }
        )
      ]
    end
  end

  defp unnecessary_stream_key_diagnostics(%Tag{} = tag, stream) do
    case find_attr(tag, ":key") do
      %Attribute{} = key_attr ->
        [
          diagnostic(
            key_attr.range,
            "phoenix.stream_unnecessary_key",
            "Streams use `id={#{stream.dom_id}}` for DOM tracking, not `:key`.",
            %{
              "kind" => "stream_unnecessary_key",
              "stream" => stream.name,
              "dom_id" => stream.dom_id
            },
            DiagnosticSeverity.warning()
          )
        ]

      nil ->
        []
    end
  end

  defp missing_stream_update_diagnostics(%Tag{} = tag, tags, stream) do
    if stream_update_container?(tag, tags) do
      []
    else
      [
        diagnostic(
          tag.name_range,
          "phoenix.stream_missing_phx_update",
          ~s(Stream `@streams.#{stream.name}` should have `phx-update="stream"` on this element or an earlier container.),
          %{
            "kind" => "stream_missing_phx_update",
            "stream" => stream.name
          },
          DiagnosticSeverity.warning()
        )
      ]
    end
  end

  defp stream_info(%Attribute{value: value}) when is_binary(value) do
    with {:ok, {:for, _meta, clauses}} <- Code.string_to_quoted("for #{value}, do: nil"),
         {:<-, _generator_meta, [pattern, enumerable]} <- Enum.find(clauses, &generator?/1),
         {:ok, stream_name} <- stream_name(enumerable) do
      case stream_pattern(pattern) do
        {:ok, dom_id, item} ->
          {:ok, %{name: stream_name, dom_id: dom_id, item: item}}

        {:invalid, item} ->
          {:invalid_pattern, %{name: stream_name, item: item}}
      end
    else
      _not_stream -> :not_stream
    end
  end

  defp stream_info(_for_attr), do: :not_stream

  defp stream_name(
         {{:., _dot_meta, [{:@, _at_meta, [{:streams, _streams_meta, _context}]}, name]},
          _call_meta, []}
       )
       when is_atom(name) do
    {:ok, Atom.to_string(name)}
  end

  defp stream_name(_enumerable), do: :error

  defp stream_pattern({dom_id, item}) do
    with {:ok, dom_id_name} <- variable_name(dom_id),
         {:ok, item_name} <- variable_name(item) do
      {:ok, dom_id_name, item_name}
    else
      _invalid -> {:invalid, "item"}
    end
  end

  defp stream_pattern(pattern) do
    case variable_name(pattern) do
      {:ok, item_name} -> {:invalid, item_name}
      :error -> {:invalid, "item"}
    end
  end

  defp variable_name({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, Atom.to_string(name)}
  end

  defp variable_name(_ast), do: :error

  defp stream_id_attr?(%Tag{} = tag, dom_id) do
    case find_attr(tag, "id") do
      %Attribute{value: ^dom_id, value_kind: :expression} -> true
      _missing_or_static -> false
    end
  end

  defp stream_update_container?(%Tag{} = tag, tags) do
    phx_update_stream?(tag) or
      tags
      |> Enum.filter(&tag_before?(&1, tag))
      |> Enum.any?(&phx_update_stream?/1)
  end

  defp phx_update_stream?(%Tag{} = tag) do
    match?(%Attribute{value: "stream"}, find_attr(tag, "phx-update"))
  end

  defp tag_before?(%Tag{} = candidate, %Tag{} = tag) do
    before_position?(candidate.range.start, tag.range.start)
  end

  defp before_position?(%{line: left_line, character: left_char}, %{
         line: right_line,
         character: right_char
       }) do
    left_line < right_line or (left_line == right_line and left_char < right_char)
  end

  defp for_item(%Attribute{value: value}) when is_binary(value) do
    with {:ok, {:for, _meta, clauses}} <- Code.string_to_quoted("for #{value}, do: nil"),
         {:<-, _generator_meta, [pattern, _enumerable]} <- Enum.find(clauses, &generator?/1),
         {:ok, item} <- first_variable_name(pattern) do
      item
    else
      _unparseable -> "item"
    end
  end

  defp for_item(_attr), do: "item"

  defp generator?({:<-, _meta, [_pattern, _enumerable]}), do: true
  defp generator?(_clause), do: false

  defp first_variable_name(pattern) do
    {_ast, variable} =
      Macro.prewalk(pattern, nil, fn
        {name, _meta, context} = node, nil
        when is_atom(name) and (is_atom(context) or is_nil(context)) ->
          {node, Atom.to_string(name)}

        node, variable ->
          {node, variable}
      end)

    case variable do
      nil -> :error
      name -> {:ok, name}
    end
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

  defp known_route_helper_reference?(%Fact{data: %{helper_base: helper_base}}, facts) do
    facts
    |> facts_by_kind(:route)
    |> Enum.any?(&(&1.data.helper_base == helper_base))
  end

  defp unknown_route_helper_diagnostic(%Fact{range: range, data: data}) do
    diagnostic(
      range,
      "phoenix.unknown_route_helper",
      ~s(Unknown route helper "#{data.helper}")
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
    name in @event_phx_attrs
  end

  defp literal_event_attr?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_event_attr?(_attr), do: false

  defp phx_attr?(%Attribute{name: "phx-" <> _suffix}), do: true
  defp phx_attr?(_attr), do: false

  defp known_phx_attr?(%Attribute{name: name}) do
    name in @known_phx_attrs or
      Enum.any?(@dynamic_phx_attr_prefixes, &String.starts_with?(name, &1))
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

  defp diagnostic(range, code, message, data \\ nil, severity \\ DiagnosticSeverity.error()) do
    %Diagnostic{
      range: range,
      severity: severity,
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
