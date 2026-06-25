defmodule PhoenixLS.Features.CodeAction.Uploads do
  @moduledoc """
  Quick fixes for LiveView upload diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind
  alias GenLSP.Structures.{CodeAction, Diagnostic, TextEdit, WorkspaceEdit}
  alias PhoenixLS.Features.CodeAction.Ranges
  alias PhoenixLS.HEEx.Document.Tag

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Tag.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{
          source: @source,
          data: %{
            "kind" => "upload_form_missing_binding",
            "binding" => binding
          }
        } = diagnostic,
        source,
        uri,
        tags
      )
      when binding in ["phx-change", "phx-submit"] do
    with %Tag{} = tag <- find_tag_by_name_range(tags, diagnostic.range),
         {:ok, range} <- Ranges.insert_range(source, tag) do
      [
        %CodeAction{
          title: ~s(Add #{binding}="#{default_event(binding)}"),
          kind: CodeActionKind.quick_fix(),
          diagnostics: [diagnostic],
          edit: %WorkspaceEdit{
            changes: %{
              uri => [
                %TextEdit{
                  range: range,
                  new_text: ~s( #{binding}="#{default_event(binding)}")
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

  def actions(_diagnostic, _source, _uri, _tags), do: []

  defp default_event("phx-change"), do: "validate"
  defp default_event("phx-submit"), do: "save"

  defp find_tag_by_name_range(tags, range) do
    Enum.find(tags, &(&1.name_range == range))
  end
end
