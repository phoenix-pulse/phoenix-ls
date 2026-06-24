defmodule PhoenixLS.Features.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.Diagnostics
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.ElixirSource

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  test "reports missing required component attrs" do
    [diagnostic] = diagnostics("<.button />")

    assert diagnostic.code == "phoenix.missing_required_attr"
    assert diagnostic.severity == DiagnosticSeverity.error()
    assert diagnostic.message == ~s(Missing required attr "label" for .button)
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

  test "reports invalid attr values" do
    [diagnostic] = diagnostics(~s(<.button label="Save" kind="danger" />))

    assert diagnostic.code == "phoenix.invalid_attr_value"
    assert diagnostic.message == ~s(Invalid value "danger" for .button kind)
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
  end

  test "reports bad phx event names" do
    [diagnostic] = diagnostics(~s(<button phx-click="missing">))

    assert diagnostic.code == "phoenix.unknown_event"
    assert diagnostic.message == ~s(Unknown LiveView event "missing")
  end

  test "reports unknown verified routes" do
    [diagnostic] = diagnostics(~s(<.link navigate={~p"/missing"} />))

    assert diagnostic.code == "phoenix.unknown_route"
    assert diagnostic.message == ~s(Unknown verified route "/missing")
  end

  test "returns no diagnostics for known Phoenix usage" do
    assert diagnostics(~s(<.button label="Save" kind="primary" />)) == []
    assert diagnostics(~s(<:inner_block />)) == []
    assert diagnostics(~s(<button phx-click="save">)) == []
    assert diagnostics(~s(<.link navigate={~p"/products"} />)) == []
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

        slot :inner_block

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
end
