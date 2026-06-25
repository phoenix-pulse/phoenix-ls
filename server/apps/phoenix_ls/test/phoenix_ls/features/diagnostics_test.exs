defmodule PhoenixLS.Features.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.Diagnostics
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @controller_uri "file:///tmp/app/lib/app_web/controllers/page_controller.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

  test "reports missing required component attrs" do
    [diagnostic] = diagnostics("<.button />")

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Missing required attr "label" for .button)

    assert diagnostic.data == %{
             "kind" => "missing_required_attr",
             "tag" => ".button",
             "attr" => "label"
           }
  end

  test "reports missing required attrs on remote component tags" do
    [diagnostic] = diagnostics("<CoreComponents.button />")

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.message == ~s(Missing required attr "label" for CoreComponents.button)
  end

  test "reports unknown component attrs" do
    [diagnostic] = diagnostics(~s(<.button label="Save" unknown="x" />))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for .button)
  end

  test "reports unknown attrs on remote component tags" do
    [diagnostic] = diagnostics(~s(<CoreComponents.button label="Save" unknown="x" />))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for CoreComponents.button)
  end

  test "reports unknown slots" do
    [diagnostic] = diagnostics("<:footer />")

    assert diagnostic.code == "phoenix.unknown_slot"
    assert diagnostic.message == ~s(Unknown slot ":footer")
  end

  test "reports unknown slot attrs" do
    [diagnostic] = diagnostics(~s(<:inner_block unknown="x" />))

    assert diagnostic.code == "phoenix.unknown_attr"
    assert diagnostic.message == ~s(Unknown attr "unknown" for :inner_block)
  end

  test "reports invalid attr values" do
    [diagnostic] = diagnostics(~s(<.button label="Save" kind="danger" />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for .button kind)

    assert diagnostic.data == %{
             "kind" => "invalid_attr_value",
             "tag" => ".button",
             "attr" => "kind",
             "value" => "danger",
             "values" => ["primary", "secondary"]
           }
  end

  test "reports invalid attr values on remote component tags" do
    [diagnostic] = diagnostics(~s(<CoreComponents.button label="Save" kind="danger" />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for CoreComponents.button kind)
  end

  test "reports missing LiveComponent id and module attrs" do
    diagnostics = diagnostics("<.live_component />")

    assert Enum.map(diagnostics, & &1.code) == [
             "phoenix.missing_live_component_attr",
             "phoenix.missing_live_component_attr"
           ]

    assert Enum.map(diagnostics, & &1.message) == [
             ~s(Missing required attr "id" for .live_component),
             ~s(Missing required attr "module" for .live_component)
           ]

    assert Enum.map(diagnostics, & &1.data) == [
             %{
               "kind" => "missing_live_component_attr",
               "tag" => ".live_component",
               "attr" => "id"
             },
             %{
               "kind" => "missing_live_component_attr",
               "tag" => ".live_component",
               "attr" => "module"
             }
           ]
  end

  test "reports bad phx event names" do
    [diagnostic] = diagnostics(~s(<button phx-click="missing">))

    assert diagnostic.code == "phoenix.unknown_event"
    assert diagnostic.message == ~s(Unknown LiveView event "missing")
  end

  test "does not report expression-based phx event values as unknown events" do
    assert diagnostics(~S|<button phx-click={JS.show(to: "#modal")} />|) == []
  end

  test "reports unknown phx attribute names" do
    [diagnostic] = diagnostics(~s(<button phx-clik="save">))

    assert diagnostic.code == "phoenix.unknown_phx_attr"
    assert diagnostic.message == ~s(Unknown Phoenix attr "phx-clik")
  end

  test "does not report known non-event phx attrs as unknown events" do
    assert diagnostics(
             ~s(<div phx-hook="Map" phx-debounce="300" phx-throttle="1000" phx-feedback-for="user[email]" />)
           ) == []
  end

  test "reports HTML :for loops without DOM tracking" do
    [diagnostic] = diagnostics(~s(<div :for={item <- @items}>{item.name}</div>))

    assert diagnostic.code == "phoenix.for_missing_key"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ~s(HTML element "div" with :for should have DOM tracking)

    assert diagnostic.data == %{
             "kind" => "for_missing_key",
             "tag" => "div",
             "item" => "item"
           }
  end

  test "does not require :key for tracked or component :for loops" do
    assert diagnostics(~s(<div :for={item <- @items} :key={item.id}>{item.name}</div>)) == []
    assert diagnostics(~s(<div :for={item <- @items} id={item.id}>{item.name}</div>)) == []

    assert diagnostics("""
           <div phx-update="stream">
             <div :for={{dom_id, item} <- @streams.items} id={dom_id}>{item.name}</div>
           </div>
           """) == []

    assert diagnostics(~s(<.card :for={item <- @items} />)) == []
  end

  test "reports stream loops without tuple destructuring" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={user <- @streams.users} id={user.id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_invalid_pattern"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message =~ "{dom_id, user} <- @streams.users"
  end

  test "reports stream loops without dom id tracking" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={{dom_id, user} <- @streams.users}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_missing_id"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message =~ "id={dom_id}"
  end

  test "reports stream loops without phx-update stream container" do
    [diagnostic] =
      diagnostics("""
      <table>
        <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_missing_phx_update"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ~s(phx-update="stream")
  end

  test "reports unnecessary stream :key usage" do
    [diagnostic] =
      diagnostics("""
      <table phx-update="stream">
        <tr :for={{dom_id, user} <- @streams.users} :key={user.id} id={dom_id}>
          <td>{user.name}</td>
        </tr>
      </table>
      """)

    assert diagnostic.code == "phoenix.stream_unnecessary_key"
    assert diagnostic.severity == DiagnosticSeverity.warning()
    assert diagnostic.message =~ ":key"
    assert diagnostic.message =~ "id={dom_id}"
  end

  test "reports unknown verified routes" do
    [diagnostic] = diagnostics(~s(<.link navigate={~p"/missing"} />))

    assert diagnostic.code == "phoenix.unknown_route"
    assert diagnostic.message == ~s(Unknown verified route "/missing")
  end

  test "reports unknown controller render templates" do
    [diagnostic] = Diagnostics.diagnostics(@controller_uri, controller_facts(:missing))

    assert diagnostic.code == "phoenix.unknown_template"
    assert diagnostic.message == ~s(Unknown template "missing.html.heex")
  end

  test "reports unknown route helpers" do
    facts =
      route_helper_facts("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.missing_path(conn, :index)
        end
      end
      """)

    [diagnostic] = Diagnostics.diagnostics(@controller_uri, facts)

    assert diagnostic.code == "phoenix.unknown_route_helper"
    assert diagnostic.message == ~s(Unknown route helper "missing_path")
  end

  test "returns no diagnostics for known Phoenix usage" do
    assert diagnostics(~s(<.button label="Save" kind="primary" />)) == []
    assert diagnostics(~s(<:inner_block />)) == []
    assert diagnostics(~s(<:inner_block class="p-2" />)) == []
    assert diagnostics(~s(<button phx-click="save">)) == []
    assert diagnostics(~s(<.link navigate={~p"/products"} />)) == []
  end

  test "returns no diagnostics for known controller render templates" do
    facts = controller_facts(:index) ++ Template.facts(@template_uri, "<h1>Index</h1>")

    assert Diagnostics.diagnostics(@controller_uri, facts) == []
  end

  test "returns no diagnostics for known route helpers" do
    facts =
      route_helper_facts("""
      defmodule AppWeb.PageController do
        def show(conn, _params) do
          Routes.product_path(conn, :index)
        end
      end
      """)

    assert Diagnostics.diagnostics(@controller_uri, facts) == []
  end

  defp diagnostics(source) do
    {:ok, document} = Parser.parse(source)

    result = Diagnostics.diagnostics(document, facts())

    assert Enum.all?(result, &match?(%Diagnostic{source: "PhoenixLS"}, &1))

    result
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true
        attr :kind, :string, values: ["primary", "secondary"]

        slot :inner_block do
          attr :class, :string
        end

        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end
      end

      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/products", ProductLive.Index, :index
        end
      end

      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("save", %{}, socket) do
          {:noreply, socket}
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp controller_facts(template) do
    {:ok, facts} =
      ElixirSource.facts(@controller_uri, """
      defmodule AppWeb.PageController do
        def index(conn, _params) do
          render(conn, :#{template})
        end
      end
      """)

    facts
  end

  defp route_helper_facts(source) do
    {:ok, controller_facts} = ElixirSource.facts(@controller_uri, source)

    controller_facts ++
      elem(
        ElixirSource.facts(@uri, """
        defmodule AppWeb.Router do
          use Phoenix.Router

          scope "/", AppWeb do
            live "/products", ProductLive.Index, :index
          end
        end
        """),
        1
      )
  end
end
