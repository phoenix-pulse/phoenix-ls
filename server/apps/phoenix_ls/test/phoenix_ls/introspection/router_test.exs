defmodule PhoenixLS.Introspection.RouterTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Router

  @uri "file:///tmp/app/lib/app_web/router.ex"
  @provenance %{source: :test}

  test "extracts scoped Phoenix route facts with source ranges" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        pipe_through :browser
        live "/products/:id", ProductLive.Show, :show
        get "/products/:id/edit", ProductController, :edit
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert Enum.map(facts, & &1.id) == [
             "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show",
             "AppWeb.Router:get:/products/:id/edit:AppWeb.ProductController:edit"
           ]

    assert [live_route, get_route] = facts

    assert live_route.kind == :route
    assert live_route.uri == @uri
    assert live_route.range.start.line == 5
    assert live_route.range.start.character == 4

    assert live_route.data == %{
             router: "AppWeb.Router",
             verb: :live,
             path: "/products/:id",
             plug: "AppWeb.ProductLive.Show",
             action: :show,
             scope_path: "/",
             scope_module: "AppWeb"
           }

    assert get_route.kind == :route
    assert get_route.data.verb == :get
    assert get_route.data.path == "/products/:id/edit"
    assert get_route.data.plug == "AppWeb.ProductController"
    assert get_route.data.action == :edit
  end

  test "ignores dynamic route paths without raising" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        get path(), PageController, :show
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance) == []
  end
end
