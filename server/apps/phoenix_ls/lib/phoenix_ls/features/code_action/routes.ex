defmodule PhoenixLS.Features.CodeAction.Routes do
  @moduledoc """
  Quick fixes for verified route diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    Diagnostic,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.HEEx.Document.Attribute
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Index.Fact

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), [PhoenixLS.HEEx.Document.Tag.t()], [Fact.t()]) :: [
          CodeAction.t()
        ]
  def actions(
        %Diagnostic{source: @source, code: "phoenix.unknown_route"} = diagnostic,
        uri,
        tags,
        facts
      ) do
    quote = route_quote(tags, diagnostic.range)

    facts
    |> static_route_paths()
    |> Enum.map(&route_fix(diagnostic, uri, quote, &1))
  end

  def actions(_diagnostic, _uri, _tags, _facts), do: []

  defp route_fix(diagnostic, uri, quote, path) do
    %CodeAction{
      title: ~s(Change route to "#{path}"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: diagnostic.range,
              new_text: "~p#{quote}#{path}#{quote}"
            }
          ]
        }
      }
    }
  end

  defp static_route_paths(facts) do
    facts
    |> Facts.by_kind(:route)
    |> Enum.filter(&match?(%{path_params: []}, &1.data))
    |> Enum.map(& &1.data.path)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp route_quote(tags, range) do
    case find_attr(tags, range) do
      %Attribute{value: "~p'" <> _path} -> "'"
      _attr -> ~s(")
    end
  end

  defp find_attr(tags, range) do
    tags
    |> Enum.flat_map(& &1.attrs)
    |> Enum.find(&(&1.value_range == range or &1.range == range))
  end
end
