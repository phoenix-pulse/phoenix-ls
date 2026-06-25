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
  alias PhoenixLS.HEEx.Document.Tag
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
      [
        %CodeAction{
          title: ~s(Add required attr "#{attr_name}"),
          kind: CodeActionKind.quick_fix(),
          diagnostics: [diagnostic],
          edit: %WorkspaceEdit{
            changes: %{
              uri => [
                %TextEdit{
                  range: range,
                  new_text: " #{attr_name}=#{default_value(attr)}"
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

  defp action_for_diagnostic(_diagnostic, _source, _uri, _tags, _facts), do: []

  defp find_tag(tags, tag_name, range) do
    Enum.find(tags, &(&1.name == tag_name and &1.name_range == range))
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

  defp default_value(%Fact{data: %{type: :string}}), do: ~s("")
  defp default_value(%Fact{data: %{type: :boolean}}), do: "{false}"
  defp default_value(%Fact{data: %{type: :integer}}), do: "{0}"
  defp default_value(%Fact{data: %{type: :float}}), do: "{0.0}"
  defp default_value(%Fact{data: %{type: :atom}}), do: "{:value}"
  defp default_value(_attr), do: "{nil}"

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
