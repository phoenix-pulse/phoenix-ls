defmodule PhoenixLS.Features.CodeAction do
  @moduledoc """
  Quick fixes for Phoenix diagnostics.
  """

  alias GenLSP.Structures.{CodeAction, Diagnostic}

  alias PhoenixLS.Features.CodeAction.{
    Components,
    Hooks,
    Navigation,
    RouteHelpers,
    Routes,
    Streams,
    Templates,
    Uploads
  }

  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.Fact

  @spec actions(String.t(), String.t(), [Diagnostic.t()], [Fact.t()]) :: [CodeAction.t()]
  def actions(source, uri, diagnostics, facts)
      when is_binary(source) and is_binary(uri) and is_list(diagnostics) and is_list(facts) do
    tags = source_tags(source)

    diagnostics
    |> Enum.flat_map(&action_for_diagnostic(&1, source, uri, tags, facts))
  end

  defp source_tags(source) do
    case Parser.parse(source) do
      {:ok, document} -> document.tags
      _error -> []
    end
  end

  defp action_for_diagnostic(%Diagnostic{} = diagnostic, source, uri, tags, facts) do
    Components.actions(diagnostic, source, uri, tags, facts) ++
      Streams.actions(diagnostic, source, uri, tags) ++
      Uploads.actions(diagnostic, source, uri, tags) ++
      Hooks.actions(diagnostic, uri) ++
      Navigation.actions(diagnostic, source, uri, facts) ++
      Templates.actions(diagnostic, uri, source, facts) ++
      Routes.actions(diagnostic, uri, tags, facts) ++
      RouteHelpers.actions(diagnostic, uri, facts)
  end

  defp action_for_diagnostic(_diagnostic, _source, _uri, _tags, _facts), do: []
end
