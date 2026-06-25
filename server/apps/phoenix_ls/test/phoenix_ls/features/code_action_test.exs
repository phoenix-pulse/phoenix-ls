defmodule PhoenixLS.Features.CodeActionTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.CodeActionKind
  alias GenLSP.Structures.{CodeAction, Position, Range, TextEdit, WorkspaceEdit}
  alias PhoenixLS.Features.CodeAction, as: CodeActionFeature
  alias PhoenixLS.Features.Diagnostics
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.ElixirSource

  @uri "file:///tmp/app/lib/app_web/live/page.html.heex"

  test "adds a missing required attr before a self-closing component tag closes" do
    source = "<.button />"
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Add required attr "label"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 8},
                         end: %Position{line: 0, character: 8}
                       },
                       new_text: ~s( label="")
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "returns no actions for diagnostics without Phoenix quick fixes" do
    assert CodeActionFeature.actions("<p />", @uri, [], facts()) == []
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/components/core_components.ex", """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true

        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end
      end
      """)

    facts
  end
end
