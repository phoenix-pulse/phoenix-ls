defmodule PhoenixLS.Introspection.LiveViewTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.LiveView

  @uri "file:///tmp/app/lib/app_web/live/product_live.ex"
  @provenance %{source: :test}

  test "extracts LiveView modules and literal handle_event facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("select-product", %{"id" => id}, socket) do
        {:noreply, assign(socket, :selected_id, id)}
      end

      def handle_event(event, _params, socket), do: {:noreply, socket}
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert Enum.map(facts, & &1.id) == [
             "AppWeb.ProductLive",
             "AppWeb.ProductLive:event:select-product"
           ]

    assert [live_view, event] = facts

    assert live_view.kind == :live_view
    assert live_view.data == %{module: "AppWeb.ProductLive"}

    assert event.kind == :live_event
    assert event.range.start.line == 3

    assert event.data == %{
             module: "AppWeb.ProductLive",
             event: "select-product"
           }
  end

  test "recognizes project-style live_view use macros" do
    source = """
    defmodule AppWeb.ProductLive do
      use AppWeb, :live_view
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert [%{kind: :live_view, id: "AppWeb.ProductLive"}] =
             LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)
  end
end
