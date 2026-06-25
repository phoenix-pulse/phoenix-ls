defmodule PhoenixLS.Introspection.ControllerTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Controller

  @uri "file:///tmp/app/lib/app_web/controllers/product_controller.ex"
  @provenance %{source: :test}

  test "extracts controller actions, renders, assigns, layouts, and plug assigns" do
    facts = facts(controller_source())

    assert [
             "AppWeb.ProductController",
             "AppWeb.ProductController:action:index",
             "AppWeb.ProductController:action:show"
           ] =
             facts
             |> Enum.filter(&(&1.kind in [:controller, :controller_action]))
             |> Enum.map(& &1.id)

    assert [%{data: controller}] = Enum.filter(facts, &(&1.kind == :controller))
    assert controller == %Controller.Controller{module: "AppWeb.ProductController"}

    render_facts = Enum.filter(facts, &(&1.kind == :controller_render))

    assert Enum.map(render_facts, &{&1.data.action, &1.data.template, &1.data.format}) == [
             {"index", "index", "html"},
             {"show", "show", "html"}
           ]

    assert [index_render, show_render] = render_facts

    assert index_render.data.candidate_uris == [
             "file:///tmp/app/lib/app_web/controllers/product_html/index.html.heex",
             "file:///tmp/app/lib/app_web/templates/product/index.html.heex"
           ]

    assert show_render.data.assigns == ["page_title", "product"]
    assert show_render.data.confidence == :exact

    assign_facts =
      facts
      |> Enum.filter(&(&1.kind == :controller_assign))
      |> Enum.map(&{&1.data.action, &1.data.name, &1.data.source, &1.data.confidence})
      |> Enum.sort()

    assert assign_facts == [
             {"index", "products", :assign, :exact},
             {"show", "page_title", :render_keyword, :exact},
             {"show", "product", :assign, :exact},
             {"show", "product", :render_keyword, :exact}
           ]

    assert [%{data: layout}] = Enum.filter(facts, &(&1.kind == :controller_layout))
    assert layout.action == "index"
    assert layout.layout == "admin"
    assert layout.confidence == :exact

    assert [%{data: plug_assign}] = Enum.filter(facts, &(&1.kind == :controller_plug_assign))
    assert plug_assign.plug == "load_current_user"
    assert plug_assign.name == "current_user"
    assert plug_assign.confidence == :medium
  end

  test "recognizes project-style controller use macros" do
    facts =
      facts(
        """
        defmodule AppWeb.PageController do
          use AppWeb, :controller
        end
        """,
        "AppWeb.PageController"
      )

    assert [%{kind: :controller, id: "AppWeb.PageController"}] =
             Enum.filter(facts, &(&1.kind == :controller))
  end

  defp facts(source, module \\ "AppWeb.ProductController") do
    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    Controller.facts_for_module_body(
      module,
      body,
      @uri,
      @provenance
    )
  end

  defp controller_source do
    """
    defmodule AppWeb.ProductController do
      use Phoenix.Controller

      plug :load_current_user

      def index(conn, _params) do
        conn
        |> assign(:products, [])
        |> put_layout(html: :admin)
        |> render(:index)
      end

      def show(conn, %{"id" => id}) when is_binary(id) do
        product = App.Catalog.get_product!(id)

        render(assign(conn, :product, product), :show, product: product, page_title: "Show")
      end

      defp load_current_user(conn, _opts), do: assign(conn, :current_user, nil)
    end
    """
  end
end
