defmodule PhoenixLS.Features.SourceReferenceLookup do
  @moduledoc """
  Resolves source-ranged reference facts to their indexed target facts.
  """

  alias PhoenixLS.Index.Fact

  @spec target_at(String.t(), %{line: non_neg_integer(), character: non_neg_integer()}, [Fact.t()]) ::
          Fact.t() | nil
  def target_at(uri, position, facts) when is_binary(uri) and is_list(facts) do
    facts
    |> Enum.find(&reference_at?(&1, uri, position))
    |> target(facts)
  end

  defp target(nil, _facts), do: nil

  defp target(%Fact{kind: :template_reference, data: reference}, facts) do
    Enum.find(facts, &template_match?(&1, reference))
  end

  defp target(%Fact{kind: :route_helper_reference, data: reference}, facts) do
    facts
    |> Enum.filter(&route_helper_match?(&1, reference))
    |> route_helper_target(reference)
  end

  defp target(_reference, _facts), do: nil

  defp reference_at?(
         %Fact{kind: kind, uri: fact_uri, range: range},
         uri,
         position
       )
       when fact_uri == uri and kind in [:template_reference, :route_helper_reference] do
    contains_position?(range, position)
  end

  defp reference_at?(_fact, _uri, _position), do: false

  defp template_match?(%Fact{kind: :template, uri: uri}, %{candidate_uris: candidate_uris}) do
    uri in candidate_uris
  end

  defp template_match?(_fact, _reference), do: false

  defp route_helper_match?(
         %Fact{kind: :route, data: %{helper_base: helper_base}},
         %{helper_base: helper_base}
       )
       when is_binary(helper_base),
       do: true

  defp route_helper_match?(_fact, _reference), do: false

  defp route_helper_target([], _reference), do: nil

  defp route_helper_target(routes, %{action: action}) when is_atom(action) do
    Enum.find(routes, &(&1.data.action == action)) || List.first(routes)
  end

  defp route_helper_target(routes, _reference), do: List.first(routes)

  defp contains_position?(%{start: start, end: finish}, position) do
    compare_position(start, position) != :gt and compare_position(position, finish) == :lt
  end

  defp compare_position(%{line: left_line}, %{line: right_line}) when left_line < right_line,
    do: :lt

  defp compare_position(%{line: left_line}, %{line: right_line}) when left_line > right_line,
    do: :gt

  defp compare_position(%{character: left_character}, %{character: right_character})
       when left_character < right_character,
       do: :lt

  defp compare_position(%{character: left_character}, %{character: right_character})
       when left_character > right_character,
       do: :gt

  defp compare_position(_left, _right), do: :eq
end
