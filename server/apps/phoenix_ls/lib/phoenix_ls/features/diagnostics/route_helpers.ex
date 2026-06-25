defmodule PhoenixLS.Features.Diagnostics.RouteHelpers do
  @moduledoc """
  Diagnostics for legacy `Routes.*_path/url` references.
  """

  alias PhoenixLS.Features.{Facts, RouteHelpers}
  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.Index.Fact

  @spec diagnostics(String.t(), [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    facts
    |> Facts.by_kind(:route_helper_reference)
    |> Enum.filter(&(&1.uri == uri))
    |> Enum.flat_map(&route_helper_reference_diagnostics(&1, facts))
  end

  defp route_helper_reference_diagnostics(%Fact{} = reference, facts) do
    routes = RouteHelpers.routes_for_reference(reference, facts)

    cond do
      routes == [] ->
        [unknown_route_helper_diagnostic(reference)]

      RouteHelpers.invalid_action?(reference, routes) ->
        [unknown_route_helper_action_diagnostic(reference, routes)]

      RouteHelpers.arity_mismatch?(reference, routes) ->
        [route_helper_arity_mismatch_diagnostic(reference, routes)]

      true ->
        []
    end
  end

  defp unknown_route_helper_diagnostic(%Fact{range: range, data: data}) do
    Builder.diagnostic(
      range,
      "phoenix.unknown_route_helper",
      ~s(Unknown route helper "#{data.helper}")
    )
  end

  defp unknown_route_helper_action_diagnostic(%Fact{range: range, data: data}, routes) do
    action = Atom.to_string(data.action)

    Builder.diagnostic(
      range,
      "phoenix.unknown_route_helper_action",
      ~s(Unknown action :#{action} for route helper "#{data.helper}"),
      %{
        "kind" => "unknown_route_helper_action",
        "helper" => data.helper,
        "action" => action,
        "validActions" => RouteHelpers.actions(routes)
      }
    )
  end

  defp route_helper_arity_mismatch_diagnostic(
         %Fact{range: range, data: data} = reference,
         routes
       ) do
    expected_arities = RouteHelpers.expected_arities(reference, routes)

    Builder.diagnostic(
      range,
      "phoenix.route_helper_arity_mismatch",
      ~s(Route helper "#{data.helper}" expects #{expected_arities_message(expected_arities)} arguments but got #{data.arity}),
      %{
        "kind" => "route_helper_arity_mismatch",
        "helper" => data.helper,
        "actualArity" => data.arity,
        "expectedArities" => expected_arities
      }
    )
  end

  defp expected_arities_message([arity]), do: Integer.to_string(arity)

  defp expected_arities_message(arities) do
    Enum.map_join(arities, " or ", &Integer.to_string/1)
  end
end
