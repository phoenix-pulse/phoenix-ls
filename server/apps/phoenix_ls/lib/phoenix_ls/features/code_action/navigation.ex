defmodule PhoenixLS.Features.CodeAction.Navigation do
  @moduledoc """
  Quick fixes for LiveView navigation diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind
  alias GenLSP.Structures.{CodeAction, Diagnostic, Position, Range, TextEdit, WorkspaceEdit}
  alias PhoenixLS.Features.Facts
  alias PhoenixLS.Index.Fact

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Fact.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{
          source: @source,
          code: "phoenix.missing_handle_params",
          data: %{"kind" => "missing_handle_params", "module" => module}
        } = diagnostic,
        source,
        uri,
        facts
      ) do
    with %Fact{uri: ^uri} = module_fact <- module_fact(facts, module),
         %Range{} = range <- insertion_range(module_fact),
         indent <- line_indent(source, range.start.line) do
      [
        %CodeAction{
          title: "Add handle_params/3 callback",
          kind: CodeActionKind.quick_fix(),
          diagnostics: [diagnostic],
          edit: %WorkspaceEdit{
            changes: %{
              uri => [
                %TextEdit{
                  range: range,
                  new_text: callback_text(indent)
                }
              ]
            }
          }
        }
      ]
    else
      _missing_source_context -> []
    end
  end

  def actions(_diagnostic, _source, _uri, _facts), do: []

  defp module_fact(facts, module) do
    facts
    |> Facts.by_kind(:module)
    |> Enum.find(&(&1.data.module == module))
  end

  defp insertion_range(%Fact{range: %Range{end: %Position{line: line}}}) do
    position = %Position{line: line, character: 0}

    %Range{start: position, end: position}
  end

  defp line_indent(source, line) do
    source
    |> String.split("\n", trim: false)
    |> Enum.at(line, "")
    |> String.graphemes()
    |> Enum.take_while(&(&1 in [" ", "\t"]))
    |> Enum.join()
  end

  defp callback_text(indent) do
    body_indent = indent <> "  "

    "\n" <>
      body_indent <>
      "@impl true\n" <>
      body_indent <>
      "def handle_params(_params, _uri, socket) do\n" <>
      body_indent <>
      "  {:noreply, socket}\n" <>
      body_indent <>
      "end\n\n"
  end
end
