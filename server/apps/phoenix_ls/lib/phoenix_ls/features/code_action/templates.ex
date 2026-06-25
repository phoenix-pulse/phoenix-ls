defmodule PhoenixLS.Features.CodeAction.Templates do
  @moduledoc """
  Quick fixes for controller render template diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.TemplateFacts
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Fact.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{source: @source, code: "phoenix.unknown_template"} = diagnostic,
        uri,
        source,
        facts
      )
      when is_binary(uri) and is_binary(source) and is_list(facts) do
    with %Fact{data: %{format: format}} <- template_reference(facts, diagnostic) do
      facts
      |> TemplateFacts.candidate_entries(uri)
      |> Enum.filter(&(&1.format == format))
      |> Enum.sort_by(&{&1.name, &1.uri})
      |> Enum.map(&template_fix(diagnostic, uri, source, &1))
    else
      _missing_context -> []
    end
  end

  def actions(_diagnostic, _uri, _source, _facts), do: []

  defp template_reference(facts, diagnostic) do
    facts
    |> facts_by_kind(:template_reference)
    |> Enum.find(&(&1.range == diagnostic.range))
  end

  defp template_fix(diagnostic, uri, source, entry) do
    %CodeAction{
      title: ~s(Change template to "#{entry.filename}"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: diagnostic.range,
              new_text: replacement_text(source, diagnostic.range.start, entry)
            }
          ]
        }
      }
    }
  end

  defp replacement_text(source, position, entry) do
    case source_byte_at(source, position) do
      ?: -> ":" <> entry.name
      ?" -> ~s("#{entry.name}.#{entry.format}")
      ?' -> "'#{entry.name}.#{entry.format}'"
      _other -> ":" <> entry.name
    end
  end

  defp source_byte_at(source, position) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         true <- offset < byte_size(source) do
      :binary.at(source, offset)
    else
      _invalid -> nil
    end
  end

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
