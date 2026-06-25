defmodule PhoenixLS.Features.CodeAction do
  @moduledoc """
  Quick fixes for Phoenix diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    Range,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.Features.CodeAction.Ranges
  alias PhoenixLS.Features.CodeAction.Routes
  alias PhoenixLS.Features.CodeAction.Templates
  alias PhoenixLS.Features.CodeAction.RouteHelpers
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.Fact

  @source "PhoenixLS"

  @spec actions(String.t(), String.t(), [Diagnostic.t()], [Fact.t()]) :: [CodeAction.t()]
  def actions(source, uri, diagnostics, facts)
      when is_binary(source) and is_binary(uri) and is_list(diagnostics) and is_list(facts) do
    tags = source_tags(source)

    diagnostics
    |> Enum.flat_map(&action_for_diagnostic(&1, source, uri, tags, facts))
  end

  defp source_tags(source) do
    case Parser.parse(source) do
      {:ok, document} -> document.tags
      _error -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.missing_required_attr",
           data: %{"kind" => "missing_required_attr", "tag" => tag_name, "attr" => attr_name}
         } = diagnostic,
         source,
         uri,
         tags,
         facts
       ) do
    with %Tag{} = tag <- find_tag(tags, tag_name, diagnostic.range),
         %Fact{} = attr <- attr_fact(facts, tag_name, attr_name),
         {:ok, range} <- Ranges.insert_range(source, tag) do
      [insert_attr_action(diagnostic, uri, range, attr_name, default_value(attr))]
    else
      _missing_context -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.missing_live_component_attr",
           data: %{
             "kind" => "missing_live_component_attr",
             "tag" => tag_name,
             "attr" => attr_name
           }
         } = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    with %Tag{} = tag <- find_tag(tags, tag_name, diagnostic.range),
         {:ok, range} <- Ranges.insert_range(source, tag) do
      [
        insert_attr_action(
          diagnostic,
          uri,
          range,
          attr_name,
          live_component_default_value(attr_name)
        )
      ]
    else
      _missing_context -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: code,
           data: %{"kind" => kind, "attr" => attr_name, "values" => values}
         } = diagnostic,
         _source,
         uri,
         _tags,
         _facts
       )
       when code in ["phoenix.invalid_attr_value", "phoenix.invalid_phx_attr_value"] and
              kind in ["invalid_attr_value", "invalid_phx_attr_value"] and is_list(values) do
    Enum.map(values, fn value ->
      %CodeAction{
        title: ~s(Change #{attr_name} to "#{value}"),
        kind: CodeActionKind.quick_fix(),
        diagnostics: [diagnostic],
        edit: %WorkspaceEdit{
          changes: %{
            uri => [
              %TextEdit{
                range: diagnostic.range,
                new_text: value
              }
            ]
          }
        }
      }
    end)
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.unknown_template"
         } = diagnostic,
         source,
         uri,
         _tags,
         facts
       ) do
    Templates.actions(diagnostic, uri, source, facts)
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.unknown_route"
         } = diagnostic,
         _source,
         uri,
         tags,
         facts
       ) do
    Routes.actions(diagnostic, uri, tags, facts)
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: code
         } = diagnostic,
         _source,
         uri,
         _tags,
         facts
       )
       when code in [
              "phoenix.unknown_route_helper",
              "phoenix.unknown_route_helper_action",
              "phoenix.route_helper_arity_mismatch"
            ] do
    RouteHelpers.actions(diagnostic, uri, facts)
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.for_missing_key",
           data: %{"kind" => "for_missing_key", "item" => item}
         } = diagnostic,
         _source,
         uri,
         _tags,
         _facts
       ) do
    [
      %CodeAction{
        title: "Add :key={#{item}.id}",
        kind: CodeActionKind.quick_fix(),
        diagnostics: [diagnostic],
        edit: %WorkspaceEdit{
          changes: %{
            uri => [
              %TextEdit{
                range: Ranges.zero_width(diagnostic.range.end),
                new_text: " :key={#{item}.id}"
              }
            ]
          }
        }
      }
    ]
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.stream_missing_id",
           data: %{"kind" => "stream_missing_id", "dom_id" => dom_id}
         } = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    with %Tag{} = tag <- find_tag_by_name_range(tags, diagnostic.range),
         {:ok, range} <- Ranges.insert_range(source, tag) do
      [
        text_edit_action(
          "Add id={#{dom_id}}",
          diagnostic,
          uri,
          range,
          " id={#{dom_id}}"
        )
      ]
    else
      _missing_context -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.stream_invalid_pattern",
           data: %{"kind" => "stream_invalid_pattern", "stream" => stream, "item" => item}
         } = diagnostic,
         _source,
         uri,
         _tags,
         _facts
       )
       when is_binary(stream) and is_binary(item) do
    [
      text_edit_action(
        "Use stream tuple pattern",
        diagnostic,
        uri,
        diagnostic.range,
        ":for={{dom_id, #{item}} <- @streams.#{stream}}"
      )
    ]
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.stream_missing_phx_update",
           data: %{"kind" => "stream_missing_phx_update"}
         } = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    with %Tag{} = tag <- find_tag_by_name_range(tags, diagnostic.range),
         {:ok, range} <- Ranges.insert_range(source, tag) do
      [
        text_edit_action(
          ~s(Add phx-update="stream"),
          diagnostic,
          uri,
          range,
          ~s( phx-update="stream")
        )
      ]
    else
      _missing_context -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{
           source: @source,
           code: "phoenix.stream_unnecessary_key",
           data: %{"kind" => "stream_unnecessary_key"}
         } = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    with %Attribute{} = attr <- find_attr(tags, diagnostic.range),
         {:ok, range} <- Ranges.attr_removal_range(source, attr) do
      [text_edit_action("Remove unnecessary stream :key", diagnostic, uri, range, "")]
    else
      _missing_context -> []
    end
  end

  defp action_for_diagnostic(
         %Diagnostic{} = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    cond do
      diagnostic.source == @source and diagnostic.code == "phoenix.unknown_slot" ->
        unknown_slot_action(diagnostic, uri, tags)

      diagnostic.source == @source and
          diagnostic.code in [
            "phoenix.unknown_attr",
            "phoenix.unknown_event",
            "phoenix.unknown_phx_attr"
          ] ->
        unknown_attr_action(diagnostic, source, uri, tags)

      true ->
        []
    end
  end

  defp action_for_diagnostic(_diagnostic, _source, _uri, _tags, _facts), do: []

  defp insert_attr_action(diagnostic, uri, range, attr_name, value) do
    %CodeAction{
      title: ~s(Add required attr "#{attr_name}"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: range,
              new_text: " #{attr_name}=#{value}"
            }
          ]
        }
      }
    }
  end

  defp text_edit_action(title, diagnostic, uri, range, new_text) do
    %CodeAction{
      title: title,
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: range,
              new_text: new_text
            }
          ]
        }
      }
    }
  end

  defp unknown_attr_action(diagnostic, source, uri, tags) do
    with %Attribute{} = attr <- find_attr(tags, diagnostic.range),
         {:ok, range} <- Ranges.attr_removal_range(source, attr) do
      [
        %CodeAction{
          title: ~s(Remove unknown attr "#{attr.name}"),
          kind: CodeActionKind.quick_fix(),
          diagnostics: [diagnostic],
          edit: %WorkspaceEdit{
            changes: %{
              uri => [
                %TextEdit{
                  range: range,
                  new_text: ""
                }
              ]
            }
          }
        }
      ]
    else
      _missing_context -> []
    end
  end

  defp unknown_slot_action(diagnostic, uri, tags) do
    with %Tag{kind: :slot} = tag <- find_tag_by_name_range(tags, diagnostic.range),
         %Range{} = range <- Ranges.tag_removal_range(tag) do
      [text_edit_action(~s(Remove unknown slot "#{tag.name}"), diagnostic, uri, range, "")]
    else
      _missing_context -> []
    end
  end

  defp find_tag(tags, tag_name, range) do
    Enum.find(tags, &(&1.name == tag_name and &1.name_range == range))
  end

  defp find_tag_by_name_range(tags, range) do
    Enum.find(tags, &(&1.name_range == range))
  end

  defp find_attr(tags, range) do
    tags
    |> Enum.flat_map(& &1.attrs)
    |> Enum.find(&(&1.name_range == range or &1.value_range == range or &1.range == range))
  end

  defp attr_fact(facts, tag_name, attr_name) do
    with %Fact{} = component <- ComponentLookup.component_for_tag(tag_name, facts) do
      facts
      |> facts_by_kind(:component_attr)
      |> Enum.find(&(&1.data.component == component.id and &1.data.name == attr_name))
    end
  end

  defp default_value(%Fact{data: %{type: :string}}), do: ~s("")
  defp default_value(%Fact{data: %{type: :boolean}}), do: "{false}"
  defp default_value(%Fact{data: %{type: :integer}}), do: "{0}"
  defp default_value(%Fact{data: %{type: :float}}), do: "{0.0}"
  defp default_value(%Fact{data: %{type: :atom}}), do: "{:value}"
  defp default_value(_attr), do: "{nil}"

  defp live_component_default_value("id"), do: ~s("")
  defp live_component_default_value("module"), do: "{Module}"
  defp live_component_default_value(_attr), do: "{nil}"

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
