defmodule PhoenixLS.Features.CodeAction do
  @moduledoc """
  Quick fixes for Phoenix diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    Position,
    Range,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @source "PhoenixLS"

  @spec actions(String.t(), String.t(), [Diagnostic.t()], [Fact.t()]) :: [CodeAction.t()]
  def actions(source, uri, diagnostics, facts)
      when is_binary(source) and is_binary(uri) and is_list(diagnostics) and is_list(facts) do
    with {:ok, document} <- Parser.parse(source) do
      diagnostics
      |> Enum.flat_map(&action_for_diagnostic(&1, source, uri, document.tags, facts))
    else
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
         {:ok, range} <- insert_range(source, tag) do
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
         {:ok, range} <- insert_range(source, tag) do
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
                range: zero_width_range(diagnostic.range.end),
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
         {:ok, range} <- insert_range(source, tag) do
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
           code: "phoenix.stream_missing_phx_update",
           data: %{"kind" => "stream_missing_phx_update"}
         } = diagnostic,
         source,
         uri,
         tags,
         _facts
       ) do
    with %Tag{} = tag <- find_tag_by_name_range(tags, diagnostic.range),
         {:ok, range} <- insert_range(source, tag) do
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
         {:ok, range} <- attr_removal_range(source, attr) do
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
    if diagnostic.source == @source and diagnostic.code == "phoenix.unknown_attr" do
      unknown_attr_action(diagnostic, source, uri, tags)
    else
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
         {:ok, range} <- attr_removal_range(source, attr) do
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

  defp find_tag(tags, tag_name, range) do
    Enum.find(tags, &(&1.name == tag_name and &1.name_range == range))
  end

  defp find_tag_by_name_range(tags, range) do
    Enum.find(tags, &(&1.name_range == range))
  end

  defp find_attr(tags, range) do
    tags
    |> Enum.flat_map(& &1.attrs)
    |> Enum.find(&(&1.name_range == range or &1.range == range))
  end

  defp attr_fact(facts, tag_name, attr_name) do
    with %Fact{} = component <- ComponentLookup.component_for_tag(tag_name, facts) do
      facts
      |> facts_by_kind(:component_attr)
      |> Enum.find(&(&1.data.component == component.id and &1.data.name == attr_name))
    end
  end

  defp insert_range(source, %Tag{} = tag) do
    with {:ok, end_offset} <- Positions.lsp_position_to_offset(source, tag.range.end),
         true <- end_offset > 0,
         {:ok, insert_offset} <- insert_offset(source, end_offset - 1, tag.self_closing?),
         {:ok, position} <- Positions.offset_to_lsp_position(source, insert_offset) do
      position = %Position{line: position.line, character: position.character}

      {:ok, %Range{start: position, end: position}}
    else
      _error -> :error
    end
  end

  defp attr_removal_range(source, %Attribute{range: range}) do
    with {:ok, start_offset} <- Positions.lsp_position_to_offset(source, range.start),
         {:ok, start} <-
           Positions.offset_to_lsp_position(
             source,
             rewind_inline_whitespace(source, start_offset)
           ) do
      {:ok, %Range{start: position(start), end: range.end}}
    else
      _error -> :error
    end
  end

  defp insert_offset(_source, gt_offset, false), do: {:ok, gt_offset}

  defp insert_offset(source, gt_offset, true) do
    with {:ok, slash_offset} <- previous_non_whitespace(source, gt_offset - 1) do
      {:ok, rewind_whitespace(source, slash_offset - 1)}
    end
  end

  defp previous_non_whitespace(_source, offset) when offset < 0, do: :error

  defp previous_non_whitespace(source, offset) do
    if whitespace_at?(source, offset) do
      previous_non_whitespace(source, offset - 1)
    else
      {:ok, offset}
    end
  end

  defp rewind_whitespace(_source, offset) when offset < 0, do: 0

  defp rewind_whitespace(source, offset) do
    if whitespace_at?(source, offset) do
      rewind_whitespace(source, offset - 1)
    else
      offset + 1
    end
  end

  defp whitespace_at?(source, offset) do
    :binary.at(source, offset) in [?\s, ?\t, ?\n, ?\r]
  end

  defp rewind_inline_whitespace(_source, 0), do: 0

  defp rewind_inline_whitespace(source, offset) do
    previous_offset = offset - 1

    if inline_whitespace_at?(source, previous_offset) do
      rewind_inline_whitespace(source, previous_offset)
    else
      offset
    end
  end

  defp inline_whitespace_at?(source, offset) when offset >= 0 do
    :binary.at(source, offset) in [?\s, ?\t]
  end

  defp inline_whitespace_at?(_source, _offset), do: false

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end

  defp zero_width_range(%Position{} = position), do: %Range{start: position, end: position}

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
