defmodule PhoenixLS.Features.CodeAction.Components do
  @moduledoc """
  Quick fixes for component, slot, and Phoenix attribute diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    Range,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.CodeAction.Ranges
  alias PhoenixLS.Features.ComponentLookup
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Tag.t()], [Fact.t()]) :: [CodeAction.t()]
  def actions(
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

  def actions(
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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.missing_required_slot",
          data: %{"kind" => "missing_required_slot", "tag" => tag_name, "slot" => slot_name}
        } = diagnostic,
        source,
        uri,
        tags,
        _facts
      ) do
    with %Tag{} = tag <- find_tag(tags, tag_name, diagnostic.range),
         %CodeAction{} = action <- insert_slot_action(diagnostic, source, uri, tag, slot_name) do
      [action]
    else
      _missing_context -> []
    end
  end

  def actions(
        %Diagnostic{
          source: @source,
          code: code,
          data: %{"kind" => kind, "attr" => attr_name, "values" => values} = data
        } = diagnostic,
        _source,
        uri,
        _tags,
        _facts
      )
      when code in ["phoenix.invalid_attr_value", "phoenix.invalid_phx_attr_value"] and
             kind in ["invalid_attr_value", "invalid_phx_attr_value"] and is_list(values) do
    replacement_values = Map.get(data, "replacementValues", values)

    values
    |> Enum.zip(replacement_values)
    |> Enum.map(fn {value, replacement_value} ->
      %CodeAction{
        title: ~s(Change #{attr_name} to "#{value}"),
        kind: CodeActionKind.quick_fix(),
        diagnostics: [diagnostic],
        edit: %WorkspaceEdit{
          changes: %{
            uri => [
              %TextEdit{
                range: diagnostic.range,
                new_text: replacement_value
              }
            ]
          }
        }
      }
    end)
  end

  def actions(%Diagnostic{} = diagnostic, source, uri, tags, _facts) do
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

  def actions(_diagnostic, _source, _uri, _tags, _facts), do: []

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

  defp insert_slot_action(diagnostic, source, uri, %Tag{self_closing?: true} = tag, slot_name) do
    with opening_text when is_binary(opening_text) <- self_closing_opening_text(source, tag) do
      text_edit_action(
        ~s(Add required slot ":#{slot_name}"),
        diagnostic,
        uri,
        tag.range,
        expanded_component_text(opening_text, tag.name, slot_name, tag_indent(tag))
      )
    else
      _missing_source -> nil
    end
  end

  defp insert_slot_action(
         diagnostic,
         _source,
         uri,
         %Tag{closing_range: %Range{} = closing_range} = tag,
         slot_name
       ) do
    text_edit_action(
      ~s(Add required slot ":#{slot_name}"),
      diagnostic,
      uri,
      Ranges.zero_width(closing_range.start),
      slot_block_text(slot_name, tag_indent(tag))
    )
  end

  defp insert_slot_action(_diagnostic, _source, _uri, _tag, _slot_name), do: nil

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

  defp self_closing_opening_text(source, %Tag{range: %Range{} = range}) do
    with {:ok, start_offset} <- Positions.lsp_position_to_offset(source, range.start),
         {:ok, end_offset} <- Positions.lsp_position_to_offset(source, range.end),
         true <- start_offset <= end_offset,
         true <- end_offset <= byte_size(source) do
      source
      |> binary_part(start_offset, end_offset - start_offset)
      |> String.trim_trailing()
      |> String.trim_trailing(">")
      |> String.trim_trailing()
      |> String.trim_trailing("/")
      |> String.trim_trailing()
      |> Kernel.<>(">")
    else
      _invalid_range -> nil
    end
  end

  defp expanded_component_text(opening_text, tag_name, slot_name, indent) do
    [
      opening_text,
      slot_line(slot_name, indent <> "  "),
      "#{indent}</#{tag_name}>"
    ]
    |> Enum.join("\n")
  end

  defp slot_block_text(slot_name, indent) do
    "\n#{slot_line(slot_name, indent <> "  ")}\n#{indent}"
  end

  defp slot_line(slot_name, indent), do: "#{indent}<:#{slot_name}></:#{slot_name}>"

  defp tag_indent(%Tag{range: %{start: %{character: character}}}) when is_integer(character) do
    String.duplicate(" ", character)
  end

  defp tag_indent(_tag), do: ""

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

  defp attr_fact(facts, ":" <> slot_name, attr_name) do
    facts
    |> Facts.by_kind(:component_slot_attr)
    |> Enum.find(&(&1.data.slot == slot_name and &1.data.name == attr_name))
  end

  defp attr_fact(facts, tag_name, attr_name) do
    with %Fact{} = component <- ComponentLookup.component_for_tag(tag_name, facts) do
      facts
      |> Facts.by_kind(:component_attr)
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
end
