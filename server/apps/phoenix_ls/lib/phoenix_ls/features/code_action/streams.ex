defmodule PhoenixLS.Features.CodeAction.Streams do
  @moduledoc """
  Quick fixes for HEEx tracking and LiveView stream diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.CodeAction.Ranges
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Tag.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.for_missing_key",
          data: %{"kind" => "for_missing_key", "item" => item}
        } = diagnostic,
        _source,
        uri,
        _tags
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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.stream_missing_id",
          data: %{"kind" => "stream_missing_id", "dom_id" => dom_id}
        } = diagnostic,
        source,
        uri,
        tags
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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.stream_invalid_pattern",
          data: %{"kind" => "stream_invalid_pattern", "stream" => stream, "item" => item}
        } = diagnostic,
        _source,
        uri,
        _tags
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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.stream_missing_phx_update",
          data: %{"kind" => "stream_missing_phx_update"}
        } = diagnostic,
        source,
        uri,
        tags
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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.stream_unnecessary_key",
          data: %{"kind" => "stream_unnecessary_key"}
        } = diagnostic,
        source,
        uri,
        tags
      ) do
    with %Attribute{} = attr <- find_attr(tags, diagnostic.range),
         {:ok, range} <- Ranges.attr_removal_range(source, attr) do
      [text_edit_action("Remove unnecessary stream :key", diagnostic, uri, range, "")]
    else
      _missing_context -> []
    end
  end

  def actions(_diagnostic, _source, _uri, _tags), do: []

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

  defp find_tag_by_name_range(tags, range) do
    Enum.find(tags, &(&1.name_range == range))
  end

  defp find_attr(tags, range) do
    tags
    |> Enum.flat_map(& &1.attrs)
    |> Enum.find(&(&1.name_range == range or &1.value_range == range or &1.range == range))
  end
end
