defmodule PhoenixLS.Features.CodeActionTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.CodeActionKind
  alias GenLSP.Structures.{CodeAction, Position, Range, TextEdit, WorkspaceEdit}
  alias PhoenixLS.Features.CodeAction, as: CodeActionFeature
  alias PhoenixLS.Features.Diagnostics
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template

  @uri "file:///tmp/app/lib/app_web/live/page.html.heex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

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

  test "removes unknown phx attrs" do
    source = ~s(<button phx-clik="save">)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Remove unknown attr "phx-clik"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 7},
                         end: %Position{line: 0, character: 23}
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

  test "removes attrs with unknown LiveView event values" do
    source = ~s(<button phx-click="missing">)
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Remove unknown attr "phx-click"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 7},
                         end: %Position{line: 0, character: 27}
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

  test "replaces unknown verified routes with known static routes" do
    source = ~s(<.link navigate={~p"/prodcts"} />)
    facts = facts() ++ route_facts()
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts)

    assert [
             %CodeAction{
               title: ~s(Change route to "/products"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 17},
                         end: %Position{line: 0, character: 29}
                       },
                       new_text: ~s(~p"/products")
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts)

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "removes self-closing unknown slots" do
    source = "<:footer />"
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Remove unknown slot ":footer"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 0},
                         end: %Position{line: 0, character: 11}
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

  test "removes unknown slot blocks" do
    source = "<:footer>Body</:footer>"
    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: ~s(Remove unknown slot ":footer"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 0, character: 0},
                         end: %Position{line: 0, character: 23}
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

  test "rewrites invalid stream patterns to tuple destructuring" do
    source =
      ~s(<table phx-update="stream"><tr :for={user <- @streams.users} id={user.id}></tr></table>)

    {:ok, document} = Parser.parse(source)
    [diagnostic] = Diagnostics.diagnostics(document, facts())

    assert [
             %CodeAction{
               title: "Use stream tuple pattern",
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @uri => [
                     %TextEdit{
                       range: range,
                       new_text: ":for={{dom_id, user} <- @streams.users}"
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @uri, [diagnostic], facts())

    assert range == diagnostic.range
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

  test "replaces invalid route helper actions with valid actions" do
    source = """
    defmodule AppWeb.PageController do
      def show(conn, _params) do
        Routes.product_path(conn, :edit)
      end
    end
    """

    facts = route_helper_facts(source)
    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert [
             %CodeAction{
               title: "Change route action to :index",
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @controller_uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 2, character: 30},
                         end: %Position{line: 2, character: 35}
                       },
                       new_text: ":index"
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @controller_uri, [diagnostic], facts)

    assert quick_fix == CodeActionKind.quick_fix()
  end

  test "replaces unknown render templates with known templates" do
    source = """
    defmodule AppWeb.PageController do
      def show(conn, _params) do
        render(conn, :missing)
      end
    end
    """

    facts = template_reference_facts(source)
    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert [
             %CodeAction{
               title: ~s(Change template to "index.html.heex"),
               kind: quick_fix,
               diagnostics: [^diagnostic],
               edit: %WorkspaceEdit{
                 changes: %{
                   @controller_uri => [
                     %TextEdit{
                       range: %Range{
                         start: %Position{line: 2, character: 17},
                         end: %Position{line: 2, character: 25}
                       },
                       new_text: ":index"
                     }
                   ]
                 }
               }
             }
           ] = CodeActionFeature.actions(source, @controller_uri, [diagnostic], facts)

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

  defp route_helper_facts(source) do
    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, source)

    {:ok, router_facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive.Index, :index
        end
      end
      """)

    controller_facts ++ router_facts
  end

  defp route_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive.Index, :index
          live "/products/:id", ProductLive.Show, :show
        end
      end
      """)

    facts
  end

  defp template_reference_facts(source) do
    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, source)

    controller_facts ++ Template.facts(@template_uri, "<h1>Index</h1>")
  end
end
