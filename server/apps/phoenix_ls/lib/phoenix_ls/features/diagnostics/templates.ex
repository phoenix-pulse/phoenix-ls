defmodule PhoenixLS.Features.Diagnostics.Templates do
  @moduledoc """
  Diagnostics for controller/template references.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Index.Fact

  @spec diagnostics(String.t(), [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    template_uris =
      facts
      |> Facts.by_kind(:template)
      |> MapSet.new(& &1.uri)

    facts
    |> template_references(uri)
    |> Enum.reject(&non_html_controller_reference?(&1, facts))
    |> Enum.reject(&known_template_reference?(&1, template_uris))
    |> Enum.map(&unknown_template_diagnostic/1)
  end

  defp template_references(facts, uri) do
    token_references =
      facts
      |> Facts.by_kind(:template_reference)
      |> Enum.filter(&(&1.uri == uri))

    controller_renders =
      facts
      |> Facts.by_kind(:controller_render)
      |> Enum.filter(&(&1.uri == uri))
      |> Enum.reject(&shadowed_by_token_reference?(&1, token_references))

    token_references ++ controller_renders
  end

  defp shadowed_by_token_reference?(%Fact{} = render, references) do
    Enum.any?(references, &same_render_reference?(render, &1))
  end

  defp same_render_reference?(%Fact{} = render, %Fact{} = reference) do
    render.data.template == reference.data.template and
      render.data.format == reference.data.format and
      contains_range?(render.range, reference.range)
  end

  defp non_html_controller_reference?(%Fact{} = reference, facts) do
    case controller_render_for(reference, facts) do
      %Fact{} = render -> json_only_controller_render?(render, facts)
      nil -> false
    end
  end

  defp controller_render_for(%Fact{kind: :controller_render} = render, _facts), do: render

  defp controller_render_for(%Fact{kind: :template_reference} = reference, facts) do
    facts
    |> Facts.by_kind(:controller_render)
    |> Enum.find(&same_render_reference?(&1, reference))
  end

  defp controller_render_for(_reference, _facts), do: nil

  defp json_only_controller_render?(%Fact{} = render, facts) do
    matching_routes =
      facts
      |> Facts.by_kind(:route)
      |> Enum.filter(&route_targets_render?(&1, render))

    matching_routes != [] and
      Enum.all?(matching_routes, &known_non_html_route?(&1, facts))
  end

  defp route_targets_render?(%Fact{data: route}, %Fact{data: render}) do
    route.plug == render.module and action_name(route.action) == render.action
  end

  defp route_targets_render?(_route, _render), do: false

  defp known_non_html_route?(%Fact{} = route, facts) do
    case route_formats(route, facts) do
      [] -> false
      formats -> "html" not in formats
    end
  end

  defp route_formats(%Fact{data: route}, facts) do
    facts
    |> Facts.by_kind(:pipeline)
    |> Enum.filter(&(&1.data.router == route.router and &1.data.name in route.pipelines))
    |> Enum.flat_map(& &1.data.formats)
    |> Enum.uniq()
  end

  defp known_template_reference?(%Fact{data: %{candidate_uris: candidate_uris}}, template_uris) do
    Enum.any?(candidate_uris, &MapSet.member?(template_uris, &1))
  end

  defp unknown_template_diagnostic(%Fact{range: range, data: data}) do
    Builder.diagnostic(
      range,
      "phoenix.unknown_template",
      ~s(Unknown template "#{data.template}.#{data.format}.heex"),
      %{
        "kind" => "unknown_template",
        "template" => data.template,
        "format" => data.format,
        "candidateUris" => data.candidate_uris
      }
    )
  end

  defp contains_range?(%{start: outer_start, end: outer_end}, %{
         start: inner_start,
         end: inner_end
       }) do
    compare_position(outer_start, inner_start) != :gt and
      compare_position(inner_end, outer_end) != :gt
  end

  defp action_name(action) when is_atom(action), do: Atom.to_string(action)
  defp action_name(action) when is_binary(action), do: action
  defp action_name(_action), do: nil

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
