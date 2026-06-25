defmodule PhoenixLS.Introspection.RouterTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Router
  alias PhoenixLS.Introspection.Router.HelperReferences

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

    assert live_route.data == %Router.Route{
             router: "AppWeb.Router",
             verb: :live,
             path: "/products/:id",
             plug: "AppWeb.ProductLive.Show",
             action: :show,
             scope_path: "/",
             scope_module: "AppWeb",
             helper_base: "product",
             path_params: ["id"],
             pipelines: ["browser"],
             live_session: nil
           }

    assert get_route.kind == :route
    assert get_route.data.verb == :get
    assert get_route.data.path == "/products/:id/edit"
    assert get_route.data.plug == "AppWeb.ProductController"
    assert get_route.data.action == :edit
    assert get_route.data.helper_base == "product_edit"
    assert get_route.data.path_params == ["id"]
    assert get_route.data.pipelines == ["browser"]
  end

  test "extracts helper bases and params from scoped controller routes" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/admin", AppWeb do
        get "/reports", ReportController, :index
      end

      scope "/billing", AppWeb do
        get "/invoices/:invoice_id", InvoiceController, :show
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert Enum.map(facts, & &1.data.helper_base) == ["admin_report", "billing_invoice"]
    assert Enum.map(facts, & &1.data.path_params) == [[], ["invoice_id"]]
  end

  test "attaches accumulated pipe_through pipelines to subsequent scoped routes" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        pipe_through [:browser, :load_account]

        get "/dashboard", DashboardController, :show

        scope "/admin" do
          pipe_through :require_admin

          live "/users/:id", UserLive.Show, :show
        end
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert Enum.map(facts, & &1.data.pipelines) == [
             ["browser", "load_account"],
             ["browser", "load_account", "require_admin"]
           ]

    assert Enum.map(facts, & &1.data.plug) == [
             "AppWeb.DashboardController",
             "AppWeb.UserLive.Show"
           ]
  end

  test "extracts pipeline accepted formats" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ~w(html)
      end

      pipeline :api do
        plug :accepts, ["json"]
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :pipeline))
           |> Enum.map(&{&1.data.name, &1.data.formats}) == [
             {"browser", ["html"]},
             {"api", ["json"]}
           ]
  end

  test "extracts resource, forward, and live_session route facts" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/admin", AppWeb do
        pipe_through [:browser, :admin]

        resources "/products", ProductController, only: [:index, :show, :create]
        forward "/graphiql", GraphiQLPlug, schema: AppWeb.Schema

        live_session :authenticated do
          live "/products/:id/live", ProductLive.Show, :show
        end
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert facts
           |> Enum.map(&{&1.data.verb, &1.data.path, &1.data.plug, &1.data.action})
           |> Enum.sort() ==
             [
               {:forward, "/admin/graphiql", "AppWeb.GraphiQLPlug", nil},
               {:get, "/admin/products", "AppWeb.ProductController", :index},
               {:get, "/admin/products/:id", "AppWeb.ProductController", :show},
               {:live, "/admin/products/:id/live", "AppWeb.ProductLive.Show", :show},
               {:post, "/admin/products", "AppWeb.ProductController", :create}
             ]
             |> Enum.sort()

    assert facts
           |> Enum.map(&{&1.data.verb, &1.data.path, &1.data.helper_base, &1.data.path_params})
           |> Enum.sort() ==
             [
               {:forward, "/admin/graphiql", "admin_graphiql", []},
               {:get, "/admin/products", "admin_product", []},
               {:get, "/admin/products/:id", "admin_product", ["id"]},
               {:live, "/admin/products/:id/live", "admin_product_live", ["id"]},
               {:post, "/admin/products", "admin_product", []}
             ]
             |> Enum.sort()

    assert Enum.map(facts, & &1.data.pipelines) ==
             List.duplicate(["browser", "admin"], 5)

    assert facts |> List.last() |> then(& &1.data.live_session) == "authenticated"
  end

  test "extracts resource path params from param option" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        resources "/products", ProductController, only: [:show], param: "slug"
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert [fact] = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert fact.data.path == "/products/:slug"
    assert fact.data.path_params == ["slug"]
  end

  test "extracts match routes for wildcard and verb lists" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/api", AppWeb do
        match :*, "/proxy/*path", ProxyController, :show
        match [:get, :post], "/sessions", SessionController, :create
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert facts
           |> Enum.map(&{&1.data.verb, &1.data.path, &1.data.plug, &1.data.action})
           |> Enum.sort() ==
             [
               {:get, "/api/sessions", "AppWeb.SessionController", :create},
               {:match, "/api/proxy/*path", "AppWeb.ProxyController", :show},
               {:post, "/api/sessions", "AppWeb.SessionController", :create}
             ]
             |> Enum.sort()

    wildcard = Enum.find(facts, &(&1.data.verb == :match))
    assert wildcard.data.helper_base == "api_proxy"
    assert wildcard.data.path_params == ["path"]
  end

  test "uses scope as helper prefixes independently from URL path segments" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/backoffice", AppWeb, as: :admin do
        get "/reports", ReportController, :index
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert [fact] = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert fact.data.path == "/backoffice/reports"
    assert fact.data.scope_path == "/backoffice"
    assert fact.data.helper_base == "admin_report"
    assert fact.data.helper_prefix == "admin"
  end

  test "respects alias false when resolving route plug modules" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/internal", AppWeb, alias: false do
        get "/health", HealthPlug, :show
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert [fact] = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert fact.data.path == "/internal/health"
    assert fact.data.plug == "HealthPlug"
    assert fact.data.scope_module == nil
    assert fact.data.helper_base == "internal_health"
  end

  test "expands nested resources with parent params and helper prefixes" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/admin", AppWeb, as: :admin do
        resources "/users", UserController, only: [:index, :show] do
          resources "/posts", PostController, only: [:index, :show, :create]
        end
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert facts
           |> Enum.map(&{&1.data.verb, &1.data.path, &1.data.helper_base, &1.data.path_params})
           |> Enum.sort() ==
             [
               {:get, "/admin/users", "admin_user", []},
               {:get, "/admin/users/:id", "admin_user", ["id"]},
               {:get, "/admin/users/:user_id/posts", "admin_user_post", ["user_id"]},
               {:get, "/admin/users/:user_id/posts/:id", "admin_user_post", ["user_id", "id"]},
               {:post, "/admin/users/:user_id/posts", "admin_user_post", ["user_id"]}
             ]
             |> Enum.sort()

    nested_show =
      Enum.find(
        facts,
        &(&1.data.path == "/admin/users/:user_id/posts/:id" and &1.data.action == :show)
      )

    assert nested_show.data.plug == "AppWeb.PostController"
    assert nested_show.data.helper_prefix == "admin_user"
  end

  test "expands singleton resources without member id params" do
    source = """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        resources "/users", UserController, only: [:show] do
          resources "/profile", ProfileController, singleton: true
        end
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Router.facts_for_module_body("AppWeb.Router", body, @uri, @provenance)

    assert Enum.any?(
             facts,
             &(&1.data.verb == :get and &1.data.path == "/users/:user_id/profile" and
                 &1.data.action == :show and &1.data.path_params == ["user_id"])
           )

    assert Enum.any?(
             facts,
             &(&1.data.verb == :get and &1.data.path == "/users/:user_id/profile/edit" and
                 &1.data.action == :edit and &1.data.path_params == ["user_id"])
           )

    refute Enum.any?(facts, &(&1.data.helper_base == "user_profile" and &1.data.action == :index))
    refute Enum.any?(facts, &(&1.data.path == "/users/:user_id/profile/:id"))
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

  test "extracts route helper references with source ranges" do
    source = """
    defmodule AppWeb.PageController do
      def show(conn, _params) do
        Routes.product_path(conn, :index)
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)

    assert [fact] = HelperReferences.facts(quoted, @uri)

    assert fact.kind == :route_helper_reference

    assert fact.data == %HelperReferences.Reference{
             helper: "product_path",
             helper_base: "product",
             variant: :path,
             action: :index,
             arity: 2
           }

    assert fact.range.start.line == 2
    assert fact.range.start.character == 11
    assert fact.range.end.character == 23
  end
end
