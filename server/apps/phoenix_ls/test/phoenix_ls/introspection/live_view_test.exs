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
             "AppWeb.ProductLive:event:select-product",
             "AppWeb.ProductLive:assign:selected_id"
           ]

    assert [live_view, event, assign] = facts

    assert live_view.kind == :live_view
    assert live_view.data == %LiveView.LiveView{module: "AppWeb.ProductLive"}

    assert event.kind == :live_event
    assert event.range.start.line == 3

    assert event.data == %LiveView.Event{
             module: "AppWeb.ProductLive",
             event: "select-product"
           }

    assert assign.kind == :assign

    assert assign.data == %LiveView.Assign{
             module: "AppWeb.ProductLive",
             name: "selected_id"
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

  test "extracts LiveView lifecycle and message handler function facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket), do: {:ok, socket}
      def handle_params(_params, _uri, socket), do: {:noreply, socket}
      def handle_info({:tick, id}, socket), do: {:noreply, assign(socket, :tick_id, id)}
      def render(assigns), do: ~H"<div />"
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :live_view_function))
           |> Enum.map(&{&1.id, &1.data.name, &1.data.type, &1.data.arity}) == [
             {"AppWeb.ProductLive:live_view_function:mount/3", "mount", :mount, 3},
             {"AppWeb.ProductLive:live_view_function:handle_params/3", "handle_params",
              :handle_params, 3},
             {"AppWeb.ProductLive:live_view_function:handle_info/2", "handle_info", :handle_info,
              2},
             {"AppWeb.ProductLive:live_view_function:render/1", "render", :render, 1}
           ]
  end

  test "ignores LiveView callback names with unsupported arities" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(socket), do: {:ok, socket}
      def handle_params(params, socket), do: {:noreply, socket}
      def handle_info(message, extra, socket), do: {:noreply, socket}
      def render(assigns, opts), do: assigns
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert Enum.filter(facts, &(&1.kind == :live_view_function)) == []
  end
end
