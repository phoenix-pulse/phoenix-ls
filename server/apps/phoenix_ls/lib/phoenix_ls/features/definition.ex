defmodule PhoenixLS.Features.Definition do
  @moduledoc """
  Go-to-definition locations for Phoenix source facts.
  """

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.PhoenixFactLookup
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec definition(CursorContext.t(), [Fact.t()]) :: Location.t() | nil
  def definition(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> location()
  end

  @spec definition(String.t(), %{line: non_neg_integer(), character: non_neg_integer()}, [
          Fact.t()
        ]) :: Location.t() | nil
  def definition(uri, position, facts) when is_binary(uri) and is_list(facts) do
    facts
    |> Enum.find(&source_reference_at?(&1, uri, position))
    |> source_reference_location(facts)
  end

  defp location(nil), do: nil

  defp location(%Fact{} = fact) do
    %Location{
      uri: fact.uri,
      range: fact.range
    }
  end

  defp source_reference_location(nil, _facts), do: nil

  defp source_reference_location(%Fact{kind: :template_reference, data: reference}, facts) do
    facts
    |> Enum.find(&template_match?(&1, reference))
    |> location()
  end

  defp source_reference_location(%Fact{kind: :route_helper_reference, data: reference}, facts) do
    facts
    |> Enum.find(&route_helper_match?(&1, reference))
    |> location()
  end

  defp source_reference_location(_reference, _facts), do: nil

  defp source_reference_at?(
         %Fact{kind: kind, uri: fact_uri, range: range},
         uri,
         position
       )
       when fact_uri == uri and kind in [:template_reference, :route_helper_reference] do
    contains_position?(range, position)
  end

  defp source_reference_at?(_fact, _uri, _position), do: false

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
