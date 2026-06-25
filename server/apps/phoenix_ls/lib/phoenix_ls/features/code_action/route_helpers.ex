defmodule PhoenixLS.Features.CodeAction.RouteHelpers do
  @moduledoc """
  Quick fixes for route helper diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    Range,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Index.Fact

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), [Fact.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.unknown_route_helper_action",
          data: %{
            "kind" => "unknown_route_helper_action",
            "helper" => helper,
            "action" => action,
            "validActions" => valid_actions
          }
        } = diagnostic,
        uri,
        facts
      )
      when is_binary(helper) and is_binary(action) and is_list(valid_actions) do
    with %Range{} = range <- route_helper_action_range(facts, diagnostic, helper, action) do
      Enum.map(valid_actions, &route_action_fix(diagnostic, uri, range, &1))
    else
      _missing_context -> []
    end
  end

  def actions(_diagnostic, _uri, _facts), do: []

  defp route_action_fix(diagnostic, uri, range, valid_action) do
    %CodeAction{
      title: "Change route action to :#{valid_action}",
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: range,
              new_text: ":#{valid_action}"
            }
          ]
        }
      }
    }
  end

  defp route_helper_action_range(facts, diagnostic, helper, action) do
    facts
    |> facts_by_kind(:route_helper_reference)
    |> Enum.find(&route_helper_reference?(&1, diagnostic, helper, action))
    |> case do
      %Fact{data: %{action_range: %Range{} = range}} -> range
      _missing -> nil
    end
  end

  defp route_helper_reference?(
         %Fact{range: range, data: %{helper: fact_helper, action: fact_action}},
         diagnostic,
         helper,
         action_text
       ) do
    fact_helper == helper and range == diagnostic.range and
      Atom.to_string(fact_action) == action_text
  end

  defp route_helper_reference?(_fact, _diagnostic, _helper, _action), do: false

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
