defmodule PhoenixLS.Features.CodeAction.Hooks do
  @moduledoc """
  Quick fixes for LiveView hook diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind
  alias GenLSP.Structures.{CodeAction, Diagnostic, TextEdit, WorkspaceEdit}

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t()) :: [CodeAction.t()]
  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.unknown_hook",
          data: %{"kind" => "unknown_hook", "knownHooks" => known_hooks}
        } = diagnostic,
        uri
      )
      when is_binary(uri) and is_list(known_hooks) do
    Enum.map(known_hooks, &hook_name_fix(diagnostic, uri, &1))
  end

  def actions(_diagnostic, _uri), do: []

  defp hook_name_fix(diagnostic, uri, hook_name) do
    %CodeAction{
      title: ~s(Change hook to "#{hook_name}"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: diagnostic.range,
              new_text: hook_name
            }
          ]
        }
      }
    }
  end
end
