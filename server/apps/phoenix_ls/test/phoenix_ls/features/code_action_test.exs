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

  test "replaces invalid attr values with each allowed value" do
    source = ~s(<.button label="Save" kind="danger" />)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    actions = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert Enum.map(actions, & &1.title) == [
             ~s(Change kind to "primary"),
             ~s(Change kind to "secondary")
           ]

    assert Enum.map(actions, fn action ->
             [%TextEdit{range: range, new_text: new_text}] = action.edit.changes[@uri]
             assert range == diagnostic.range
             new_text
           end) == ["primary", "secondary"]
  end

  test "replaces invalid phx attr values with each allowed value" do
    source = ~s(<div phx-update="morph" />)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    actions = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert Enum.map(actions, & &1.title) == [
             ~s(Change phx-update to "replace"),
             ~s(Change phx-update to "append"),
             ~s(Change phx-update to "prepend"),
             ~s(Change phx-update to "ignore"),
             ~s(Change phx-update to "stream")
           ]

    assert Enum.map(actions, fn action ->
             [%TextEdit{range: range, new_text: new_text}] = action.edit.changes[@uri]
             assert range == diagnostic.range
             new_text
           end) == ["replace", "append", "prepend", "ignore", "stream"]
  end

  test "removes unknown attrs from component tags" do
    source = ~s(<.button label="Save" unknown="x" />)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Remove unknown attr "unknown"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 21},
                         end: %Position{line: 0, character: 33}
                       },
                       new_text: ""
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "adds missing LiveComponent attrs" do
    source = "<.live_component />"
    {:ok, document} = Parser.parse(source)
    diagnostics = Diagnostics.diagnostics(document, facts())

    actions = CodeActionFeature.actions(source, @uri, diagnostics, facts())

    assert Enum.map(actions, & &1.title) == [
             ~s(Add required attr "id"),
             ~s(Add required attr "module")
           ]

    assert Enum.map(actions, fn action ->
             [%TextEdit{range: range, new_text: new_text}] = action.edit.changes[@uri]

             assert range == %Range{
                      start: %Position{line: 0, character: 16},
                      end: %Position{line: 0, character: 16}
                    }

             new_text
           end) == [~s( id=""), " module={Module}"]
  end

  test "adds :key for HTML :for loops without DOM tracking" do
    source = ~s(<div :for={item <- @items}>{item.name}</div>)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: "Add :key={item.id}",
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 26},
                         end: %Position{line: 0, character: 26}
                       },
                       new_text: " :key={item.id}"
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "adds missing stream item DOM id" do
    source = """
    <table phx-update="stream">
      <tr :for={{dom_id, user} <- @streams.users}>
        <td>{user.name}</td>
      </tr>
    </table>
    """

    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: "Add id={dom_id}",
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 1, character: 45},
                         end: %Position{line: 1, character: 45}
                       },
                       new_text: " id={dom_id}"
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "adds missing phx-update stream attribute" do
    source = """
    <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
      <td>{user.name}</td>
    </tr>
    """

    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Add phx-update="stream"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 55},
                         end: %Position{line: 0, character: 55}
                       },
                       new_text: ~s( phx-update="stream")
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "removes unnecessary stream :key" do
    source = """
    <table phx-update="stream">
      <tr :for={{dom_id, user} <- @streams.users} :key={user.id} id={dom_id}>
        <td>{user.name}</td>
      </tr>
    </table>
    """

    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: "Remove unnecessary stream :key",
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 1, character: 45},
                         end: %Position{line: 1, character: 60}
                       },
                       new_text: ""
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert quick_fix == CodeActionKind.quick_fix()
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/components/core_components.ex", """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true
        attr :kind, :string, values: ["primary", "secondary"]

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
