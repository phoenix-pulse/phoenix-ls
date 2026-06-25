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
          code: "phoenix.unknown_route_helper"
        } = diagnostic,
        uri,
        facts
      ) do
    with %Fact{data: %{variant: variant}} <- route_helper_reference(facts, diagnostic) do
      facts
      |> route_helper_names(variant)
      |> Enum.map(&route_helper_name_fix(diagnostic, uri, &1))
    else
      _missing_context -> []
    end
  end

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

  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.route_helper_arity_mismatch",
          data: %{
            "kind" => "route_helper_arity_mismatch",
            "actualArity" => actual_arity,
            "expectedArities" => expected_arities
          }
        } = diagnostic,
        uri,
        facts
      )
      when is_integer(actual_arity) and is_list(expected_arities) do
    with %Fact{} = reference <- route_helper_reference(facts, diagnostic) do
      route_missing_param_fixes(diagnostic, uri, facts, reference, actual_arity, expected_arities) ++
        route_extra_arg_fixes(diagnostic, uri, reference, actual_arity, expected_arities)
    else
      _missing_context -> []
    end
  end

  def actions(_diagnostic, _uri, _facts), do: []

  defp route_helper_name_fix(diagnostic, uri, helper_name) do
    %CodeAction{
      title: "Change route helper to #{helper_name}",
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: diagnostic.range,
              new_text: helper_name
            }
          ]
        }
      }
    }
  end

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

  defp route_missing_params_fix(diagnostic, uri, range, params) do
    %CodeAction{
      title: missing_params_title(params),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: range,
              new_text: ", " <> Enum.join(params, ", ")
            }
          ]
        }
      }
    }
  end

  defp missing_params_title([param]), do: "Add missing route param #{param}"
  defp missing_params_title(params), do: "Add missing route params #{Enum.join(params, ", ")}"

  defp route_extra_args_fix(diagnostic, uri, range, expected_arity, expected_arities) do
    %CodeAction{
      title: extra_args_title(expected_arity, expected_arities),
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
  end

  defp extra_args_title(_expected_arity, [_only_expected]) do
    "Remove extra route helper arguments"
  end

  defp extra_args_title(expected_arity, _expected_arities) do
    "Remove extra route helper arguments to match #{expected_arity} args"
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

  defp route_helper_reference(facts, diagnostic) do
    facts
    |> facts_by_kind(:route_helper_reference)
    |> Enum.find(&(&1.range == diagnostic.range))
  end

  defp route_helper_names(facts, variant) do
    facts
    |> facts_by_kind(:route)
    |> Enum.map(&route_helper_name(&1, variant))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp route_helper_name(%Fact{data: %{helper_base: helper_base}}, variant)
       when is_binary(helper_base) and variant in [:path, :url] do
    "#{helper_base}_#{variant}"
  end

  defp route_helper_name(_route, _variant), do: nil

  defp route_missing_param_fixes(
         diagnostic,
         uri,
         facts,
         reference,
         actual_arity,
         expected_arities
       ) do
    with %Range{} = range <- reference.data.arg_insert_range do
      facts
      |> route_helper_missing_params(reference, actual_arity, expected_arities)
      |> Enum.map(&route_missing_params_fix(diagnostic, uri, range, &1))
    else
      _missing_insert_range -> []
    end
  end

  defp route_extra_arg_fixes(diagnostic, uri, reference, actual_arity, expected_arities) do
    trim_ranges = reference.data.arg_trim_ranges || %{}

    expected_arities
    |> Enum.filter(&(is_integer(&1) and &1 < actual_arity))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn expected_arity ->
      case Map.fetch(trim_ranges, expected_arity) do
        {:ok, %Range{} = range} ->
          [route_extra_args_fix(diagnostic, uri, range, expected_arity, expected_arities)]

        _missing_range ->
          []
      end
    end)
  end

  defp route_helper_missing_params(facts, reference, actual_arity, expected_arities) do
    facts
    |> facts_by_kind(:route)
    |> Enum.filter(&route_for_reference?(&1, reference))
    |> Enum.filter(&(route_helper_expected_arity(&1) in expected_arities))
    |> Enum.filter(&(actual_arity < route_helper_expected_arity(&1)))
    |> Enum.map(&missing_path_params(&1, reference, actual_arity))
    |> Enum.reject(&(&1 == []))
    |> Enum.uniq()
  end

  defp route_for_reference?(
         %Fact{data: %{helper_base: helper_base, action: action}},
         %Fact{data: %{helper_base: helper_base, action: action}}
       ) do
    true
  end

  defp route_for_reference?(_route, _reference), do: false

  defp route_helper_expected_arity(%Fact{data: %{action: action, path_params: path_params}}) do
    1 + route_helper_action_arity(action) + length(path_params)
  end

  defp route_helper_action_arity(nil), do: 0
  defp route_helper_action_arity(_action), do: 1

  defp missing_path_params(%Fact{data: %{path_params: path_params}}, reference, actual_arity) do
    path_args_supplied =
      max(actual_arity - 1 - route_helper_action_arity(reference.data.action), 0)

    Enum.drop(path_params, path_args_supplied)
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
