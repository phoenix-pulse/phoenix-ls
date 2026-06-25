defmodule PhoenixLS.Features.PhoenixRequestsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Features.PhoenixRequests
  alias PhoenixLS.Index.{ElixirSource, Snapshot}
  alias PhoenixLS.Introspection.Asset.Hooks, as: AssetHooks
  alias PhoenixLS.Introspection.Template

  @source_uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

  test "lists schemas with fields and associations" do
    assert [
             %{
               "id" => "App.Catalog.Product:schema:products",
               "name" => "App.Catalog.Product",
               "module" => "App.Catalog.Product",
               "source" => "products",
               "table" => "products",
               "tableName" => "products",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => line, "character" => 2},
               "fieldsCount" => 3,
               "associationsCount" => 1,
               "fields" => [
                 %{
                   "name" => "id",
                   "type" => "id",
                   "elixirType" => ":id",
                   "primaryKey" => true,
                   "foreignKey" => false,
                   "generated" => true,
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _schema_line, "character" => 2}
                 },
                 %{
                   "name" => "name",
                   "type" => "string",
                   "elixirType" => ":string",
                   "primaryKey" => false,
                   "foreignKey" => false,
                   "generated" => false,
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _field_line, "character" => 4}
                 },
                 %{
                   "name" => "category_id",
                   "type" => "id",
                   "elixirType" => ":id",
                   "primaryKey" => false,
                   "foreignKey" => true,
                   "generated" => true,
                   "references" => "App.Catalog.Category",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _association_fk_line, "character" => 4}
                 }
               ],
               "associations" => [
                 %{
                   "name" => "category",
                   "fieldName" => "category",
                   "foreignKey" => "category_id",
                   "schema" => "App.Catalog.Category",
                   "targetModule" => "App.Catalog.Category",
                   "type" => "belongs_to",
                   "cardinality" => "many_to_one",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _association_line, "character" => 4}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listSchemas", snapshot())

    assert line > 0
  end

  test "lists components with attrs, slots, and slot attrs" do
    assert [
             %{
               "name" => "button",
               "module" => "AppWeb.CoreComponents",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 2},
               "attributesCount" => 1,
               "slotsCount" => 1,
               "attributes" => [
                 %{
                   "name" => "label",
                   "type" => "string",
                   "required" => true,
                   "doc" => "Visible label",
                   "rawType" => ":string",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _attr_line, "character" => 2}
                 }
               ],
               "slots" => [
                 %{
                   "name" => "inner_block",
                   "required" => true,
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _slot_line, "character" => 2},
                   "attributes" => [
                     %{
                       "name" => "class",
                       "type" => "string",
                       "required" => false,
                       "default" => "\"p-2\"",
                       "rawType" => ":string",
                       "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                       "location" => %{"line" => _slot_attr_line, "character" => 4}
                     }
                   ]
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listComponents", snapshot())
  end

  test "lists routes" do
    assert [
             %{
               "verb" => "live",
               "path" => "/products/:id",
               "controller" => "AppWeb.ProductLive.Show",
               "action" => "show",
               "liveModule" => "AppWeb.ProductLive.Show",
               "liveAction" => "show",
               "helperBase" => "product",
               "pathParams" => ["id"],
               "scopePath" => "/",
               "pipeline" => "browser",
               "pipelines" => ["browser"],
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 4}
             }
           ] = PhoenixRequests.handle("phoenix/listRoutes", snapshot())
  end

  test "lists expanded resource forward and live session routes" do
    {:ok, facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/admin", AppWeb do
          pipe_through [:browser, :admin]

          resources "/products", ProductController, only: [:index, :show]
          forward "/graphiql", GraphiQLPlug, schema: AppWeb.Schema

          live_session :authenticated do
            live "/products/:id/live", ProductLive.Show, :show
          end
        end
      end
      """)

    routes = PhoenixRequests.handle("phoenix/listRoutes", Snapshot.new(facts))

    assert Enum.map(routes, &{&1["verb"], &1["path"], &1["controller"], &1["action"]}) == [
             {"forward", "/admin/graphiql", "AppWeb.GraphiQLPlug", ""},
             {"get", "/admin/products", "AppWeb.ProductController", "index"},
             {"get", "/admin/products/:id", "AppWeb.ProductController", "show"},
             {"live", "/admin/products/:id/live", "AppWeb.ProductLive.Show", "show"}
           ]

    assert Enum.map(routes, & &1["pipelines"]) == List.duplicate(["browser", "admin"], 4)

    assert Enum.find(routes, &(&1["verb"] == "live"))["liveSession"] == "authenticated"
  end

  test "lists route helper metadata for editor grouping and copy commands" do
    {:ok, facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/backoffice", AppWeb, as: :admin do
          get "/reports", ReportController, :index
        end
      end
      """)

    assert [
             %{
               "path" => "/backoffice/reports",
               "controller" => "AppWeb.ReportController",
               "helperBase" => "admin_report",
               "helperName" => "admin_report_path",
               "helperPrefix" => "admin",
               "helperVariants" => ["path", "url"]
             }
           ] = PhoenixRequests.handle("phoenix/listRoutes", Snapshot.new(facts))
  end

  test "lists controller graph with routes renders templates assigns layouts and plug assigns" do
    router_uri = "file:///tmp/app/lib/app_web/router.ex"
    controller_uri = "file:///tmp/app/lib/app_web/controllers/product_controller.ex"
    template_uri = "file:///tmp/app/lib/app_web/controllers/product_html/show.html.heex"

    {:ok, router_facts} =
      ElixirSource.facts(router_uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          pipe_through :browser

          get "/products/:id", ProductController, :show
        end
      end
      """)

    {:ok, controller_facts} =
      ElixirSource.facts(controller_uri, """
      defmodule AppWeb.ProductController do
        use AppWeb, :controller

        plug :load_account

        def show(conn, %{"id" => id}) do
          conn
          |> assign(:product, id)
          |> put_layout(html: :admin)
          |> render(:show, page_title: "Product")
        end

        defp load_account(conn, _opts) do
          assign(conn, :current_account, "acct")
        end
      end
      """)

    controller_graph =
      PhoenixRequests.handle(
        "phoenix/listControllers",
        Snapshot.new(router_facts ++ controller_facts ++ Template.facts(template_uri, "<h1 />"))
      )

    assert [
             %{
               "module" => "AppWeb.ProductController",
               "name" => "AppWeb.ProductController",
               "filePath" => "/tmp/app/lib/app_web/controllers/product_controller.ex",
               "actions" => [
                 %{
                   "name" => "show",
                   "arity" => 2,
                   "routes" => [
                     %{
                       "verb" => "get",
                       "path" => "/products/:id",
                       "helperBase" => "product",
                       "filePath" => "/tmp/app/lib/app_web/router.ex"
                     }
                   ],
                   "renders" => [
                     %{
                       "template" => "show",
                       "format" => "html",
                       "templatePath" =>
                         "/tmp/app/lib/app_web/controllers/product_html/show.html.heex",
                       "assigns" => ["page_title"],
                       "confidence" => "exact"
                     }
                   ],
                   "assigns" => assigns,
                   "layouts" => [
                     %{
                       "name" => "admin",
                       "source" => "put_layout",
                       "confidence" => "exact"
                     }
                   ]
                 }
               ],
               "plugAssigns" => [
                 %{
                   "plug" => "load_account",
                   "name" => "current_account",
                   "confidence" => "medium",
                   "filePath" => "/tmp/app/lib/app_web/controllers/product_controller.ex"
                 }
               ]
             }
           ] = controller_graph

    assert Enum.map(assigns, &{&1["name"], &1["source"], &1["confidence"]}) == [
             {"page_title", "render_keyword", "exact"},
             {"product", "assign", "exact"}
           ]
  end

  test "lists templates" do
    facts =
      [
        @template_uri,
        "file:///tmp/app/lib/app_web/components/layouts/root.html.heex",
        "file:///tmp/app/lib/app_web/components/core_components/card.html.heex",
        "file:///tmp/app/lib/app_web/live/product_live/show.html.heex"
      ]
      |> Enum.flat_map(&Template.facts(&1, "<section />"))

    assert PhoenixRequests.handle("phoenix/listTemplates", Snapshot.new(facts)) == [
             %{
               "name" => "card.html",
               "format" => "heex",
               "kind" => "component",
               "filePath" => "/tmp/app/lib/app_web/components/core_components/card.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => "AppWeb.CoreComponents"
             },
             %{
               "name" => "root.html",
               "format" => "heex",
               "kind" => "layout",
               "filePath" => "/tmp/app/lib/app_web/components/layouts/root.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => "AppWeb.Layouts"
             },
             %{
               "name" => "index.html",
               "format" => "heex",
               "kind" => "controller",
               "filePath" => "/tmp/app/lib/app_web/controllers/page_html/index.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => "AppWeb.PageHTML"
             },
             %{
               "name" => "show.html",
               "format" => "heex",
               "kind" => "live_view",
               "filePath" => "/tmp/app/lib/app_web/live/product_live/show.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => "AppWeb.ProductLive.Show"
             }
           ]
  end

  test "lists legacy and colocated template variants with inferred modules" do
    facts =
      [
        "file:///tmp/app/lib/app_web/templates/page/index.html.heex",
        "file:///tmp/app/lib/app_web/templates/layout/app.html.heex",
        "file:///tmp/app/lib/app_web/components/layouts.html.heex",
        "file:///tmp/app/lib/app_web/components/core_components.html.heex",
        "file:///tmp/app/lib/app_web/live/product_live.html.heex"
      ]
      |> Enum.flat_map(&Template.facts(&1, "<section />"))

    templates =
      PhoenixRequests.handle("phoenix/listTemplates", Snapshot.new(facts))
      |> Map.new(&{&1["filePath"], &1})

    assert templates["/tmp/app/lib/app_web/templates/page/index.html.heex"] == %{
             "name" => "index.html",
             "format" => "heex",
             "kind" => "controller",
             "filePath" => "/tmp/app/lib/app_web/templates/page/index.html.heex",
             "location" => %{"line" => 0, "character" => 0},
             "module" => "AppWeb.PageView"
           }

    assert templates["/tmp/app/lib/app_web/templates/layout/app.html.heex"]["module"] ==
             "AppWeb.LayoutView"

    assert templates["/tmp/app/lib/app_web/templates/layout/app.html.heex"]["kind"] == "layout"

    assert templates["/tmp/app/lib/app_web/components/layouts.html.heex"]["module"] ==
             "AppWeb.Layouts"

    assert templates["/tmp/app/lib/app_web/components/layouts.html.heex"]["kind"] == "layout"

    assert templates["/tmp/app/lib/app_web/components/core_components.html.heex"]["module"] ==
             "AppWeb.CoreComponents"

    assert templates["/tmp/app/lib/app_web/live/product_live.html.heex"]["module"] ==
             "AppWeb.ProductLive"
  end

  test "lists LiveView events" do
    assert [
             %{
               "name" => "select-product",
               "type" => "handle_event",
               "handler" => "handle_event/3",
               "arity" => 3,
               "module" => "AppWeb.ProductLive",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 2}
             }
           ] = PhoenixRequests.handle("phoenix/listEvents", snapshot())
  end

  test "lists LiveView uploads with usage locations" do
    source =
      ~s(<form phx-change="validate" phx-submit="save"><.live_file_input upload={@uploads.avatar} /></form>)

    {:ok, upload_facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
        end
      end
      """)

    usage_facts =
      Template.upload_usage_facts(
        "file:///tmp/app/lib/app_web/live/product_live.html.heex",
        source
      )

    assert [
             %{
               "name" => "avatar",
               "module" => "AppWeb.ProductLive",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => _character},
               "options" => %{
                 "accept" => [".jpg", ".png"],
                 "max_entries" => 1
               },
               "usagesCount" => 1,
               "usages" => [
                 %{
                   "name" => "avatar",
                   "module" => "AppWeb.ProductLive",
                   "role" => "live_file_input",
                   "attribute" => "upload",
                   "tag" => ".live_file_input",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 0, "character" => _usage_character},
                   "defined" => true
                 }
               ]
             }
           ] =
             PhoenixRequests.handle(
               "phoenix/listUploads",
               Snapshot.new(upload_facts ++ usage_facts)
             )
  end

  test "lists LiveView upload callback usages" do
    {:ok, upload_facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
        end

        def handle_event("save", _params, socket) do
          consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry -> {:ok, path} end)
          cancel_upload(socket, :avatar, "ref")
          {:noreply, socket}
        end
      end
      """)

    assert [
             %{
               "name" => "avatar",
               "module" => "AppWeb.ProductLive",
               "usagesCount" => 2,
               "usages" => [
                 %{
                   "role" => "consume_uploaded_entries",
                   "function" => "consume_uploaded_entries/3",
                   "defined" => true
                 },
                 %{
                   "role" => "cancel_upload",
                   "function" => "cancel_upload/3",
                   "defined" => true
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listUploads", Snapshot.new(upload_facts))
  end

  test "lists LiveView hooks with definition and usage locations" do
    usage_source =
      ~s(<div phx-hook="PhoneNumber"></div><div phx-hook="MissingHook"></div>)

    hook_facts =
      AssetHooks.facts(
        "file:///tmp/app/priv/static/assets/app.js",
        """
        const Hooks = {}
        Hooks.PhoneNumber = {
          mounted() {}
        }
        """,
        %{source: :static_asset}
      )

    usage_facts =
      Template.hook_usage_facts(
        "file:///tmp/app/lib/app_web/live/product_live.html.heex",
        usage_source
      )

    hooks = PhoenixRequests.handle("phoenix/listHooks", Snapshot.new(hook_facts ++ usage_facts))

    assert [
             %{
               "name" => "MissingHook",
               "defined" => false,
               "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
               "location" => %{"line" => 0, "character" => _missing_character},
               "usagesCount" => 1,
               "usages" => [
                 %{
                   "name" => "MissingHook",
                   "module" => "AppWeb.ProductLive",
                   "attribute" => "phx-hook",
                   "tag" => "div",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 0, "character" => _missing_usage_character},
                   "defined" => false
                 }
               ]
             },
             %{
               "name" => "PhoneNumber",
               "defined" => true,
               "source" => "javascript_hook_map",
               "filePath" => "/tmp/app/priv/static/assets/app.js",
               "location" => %{"line" => 1, "character" => 6},
               "usagesCount" => 1,
               "usages" => [
                 %{
                   "name" => "PhoneNumber",
                   "module" => "AppWeb.ProductLive",
                   "attribute" => "phx-hook",
                   "tag" => "div",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 0, "character" => _usage_character},
                   "defined" => true
                 }
               ]
             }
           ] = hooks
  end

  test "lists colocated assets grouped by owner module" do
    source = """
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
      export default {}
    </script>

    <script :type={Phoenix.LiveView.ColocatedJS}>
      console.log("local")
    </script>

    <style :type={Phoenix.LiveView.ColocatedCSS}>
      .root {}
    </style>
    """

    facts =
      Template.colocated_asset_facts(
        "file:///tmp/app/lib/app_web/live/product_live.html.heex",
        source
      )

    assert [
             %{
               "ownerModule" => "AppWeb.ProductLive",
               "assetsCount" => 3,
               "assets" => [
                 %{
                   "kind" => "colocated_hook",
                   "typeModule" => "Phoenix.LiveView.ColocatedHook",
                   "name" => ".Sortable",
                   "generatedName" => "AppWeb.ProductLive.Sortable",
                   "tag" => "script",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 0, "character" => 0},
                   "options" => %{"name" => ".Sortable"}
                 },
                 %{
                   "kind" => "colocated_js",
                   "typeModule" => "Phoenix.LiveView.ColocatedJS",
                   "name" => nil,
                   "generatedName" => "AppWeb.ProductLive.ColocatedJS",
                   "tag" => "script",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 4, "character" => 0},
                   "options" => %{}
                 },
                 %{
                   "kind" => "colocated_css",
                   "typeModule" => "Phoenix.LiveView.ColocatedCSS",
                   "name" => nil,
                   "generatedName" => "AppWeb.ProductLive.ColocatedCSS",
                   "tag" => "style",
                   "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
                   "location" => %{"line" => 8, "character" => 0},
                   "options" => %{}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listColocatedAssets", Snapshot.new(facts))
  end

  test "lists LiveView event usages with handler mapping state" do
    {:ok, handler_facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def handle_event("save", _params, socket), do: {:noreply, socket}
      end
      """)

    usage_facts =
      Template.event_usage_facts(
        "file:///tmp/app/lib/app_web/live/product_live.html.heex",
        ~s(<button phx-click="save" /><button phx-submit="missing" />)
      )

    events =
      PhoenixRequests.handle("phoenix/listEvents", Snapshot.new(handler_facts ++ usage_facts))

    assert Enum.find(events, &(&1["source"] == "handler" and &1["name"] == "save")) ==
             %{
               "name" => "save",
               "type" => "handle_event",
               "handler" => "handle_event/3",
               "arity" => 3,
               "module" => "AppWeb.ProductLive",
               "source" => "handler",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => 3, "character" => 2}
             }

    assert Enum.find(events, &(&1["source"] == "usage" and &1["name"] == "save")) == %{
             "name" => "save",
             "type" => "phx-click",
             "handler" => "handle_event/3",
             "arity" => 3,
             "module" => "AppWeb.ProductLive",
             "source" => "usage",
             "handled" => true,
             "handlerFilePath" => "/tmp/app/lib/app_web/live/page_live.ex",
             "handlerLocation" => %{"line" => 3, "character" => 2},
             "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
             "location" => %{"line" => 0, "character" => 19},
             "attribute" => "phx-click"
           }

    assert Enum.find(events, &(&1["source"] == "usage" and &1["name"] == "missing")) == %{
             "name" => "missing",
             "type" => "phx-submit",
             "handler" => "handle_event/3",
             "arity" => 3,
             "module" => "AppWeb.ProductLive",
             "source" => "usage",
             "handled" => false,
             "filePath" => "/tmp/app/lib/app_web/live/product_live.html.heex",
             "location" => %{"line" => 0, "character" => 47},
             "attribute" => "phx-submit"
           }
  end

  test "lists LiveView modules with functions" do
    assert [
             %{
               "module" => "AppWeb.ProductLive",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _module_line, "character" => 2},
               "assigns" => [
                 %{
                   "name" => "selected_id",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _selected_assign_line, "character" => _selected_char}
                 },
                 %{
                   "name" => "tick_id",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _tick_assign_line, "character" => _tick_char}
                 }
               ],
               "functions" => [
                 %{
                   "name" => "mount",
                   "type" => "mount",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _mount_line, "character" => 2}
                 },
                 %{
                   "name" => "handle_params",
                   "type" => "handle_params",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _params_line, "character" => 2}
                 },
                 %{
                   "name" => "render",
                   "type" => "render",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _render_line, "character" => 2}
                 },
                 %{
                   "name" => "handle_event",
                   "type" => "handle_event",
                   "eventName" => "select-product",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _line, "character" => 2}
                 },
                 %{
                   "name" => "handle_info",
                   "type" => "handle_info",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _info_line, "character" => 2}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listLiveView", snapshot())
  end

  test "lists LiveView lifecycle relationships" do
    {:ok, facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          socket =
            socket
            |> start_async(:load_stats, fn -> :ok end)
            |> attach_hook(:log_events, :handle_event, fn _event, _params, socket -> {:cont, socket} end)

          {:ok, socket, temporary_assigns: [messages: []]}
        end

        def handle_async(:load_stats, {:ok, _result}, socket), do: {:noreply, socket}
        def handle_info(:tick, socket), do: {:noreply, socket}
      end
      """)

    assert [
             %{
               "module" => "AppWeb.ProductLive",
               "async" => [
                 %{
                   "name" => "load_stats",
                   "source" => "start_async",
                   "handler" => nil,
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _start_line, "character" => _start_char}
                 },
                 %{
                   "name" => "load_stats",
                   "source" => "handle_async",
                   "handler" => "handle_async/3",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _async_line, "character" => 2}
                 }
               ],
               "hooks" => [
                 %{
                   "name" => "log_events",
                   "stage" => "handle_event",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _hook_line, "character" => _hook_char}
                 }
               ],
               "messages" => [
                 %{
                   "name" => "tick",
                   "pattern" => ":tick",
                   "handler" => "handle_info/2",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _message_line, "character" => 2}
                 }
               ],
               "temporaryAssigns" => [
                 %{
                   "name" => "messages",
                   "default" => "[]",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _temporary_line, "character" => _temporary_char}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listLiveView", Snapshot.new(facts))
  end

  test "lists many-to-many association metadata for ERD explorers" do
    {:ok, facts} =
      ElixirSource.facts(@source_uri, """
      defmodule App.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          many_to_many :tags, App.Catalog.Tag,
            join_through: "products_tags",
            join_keys: [product_id: :id, tag_id: :id],
            on_replace: :delete
        end
      end
      """)

    assert [
             %{
               "associations" => [
                 %{
                   "name" => "tags",
                   "type" => "many_to_many",
                   "cardinality" => "many_to_many",
                   "targetModule" => "App.Catalog.Tag"
                 } = association
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listSchemas", Snapshot.new(facts))

    assert association["joinThrough"] == "products_tags"
    assert association["joinKeys"] == "[product_id: :id, tag_id: :id]"
    assert association["onReplace"] == "delete"
  end

  test "does not synthesize belongs_to foreign key fields when define_field is false" do
    {:ok, facts} =
      ElixirSource.facts(@source_uri, """
      defmodule App.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          field :name, :string
          belongs_to :category, App.Catalog.Category, define_field: false
        end
      end
      """)

    assert [
             %{
               "fields" => fields,
               "associations" => [
                 %{
                   "name" => "category",
                   "foreignKey" => "category_id",
                   "defineField" => false
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listSchemas", Snapshot.new(facts))

    assert Enum.map(fields, & &1["name"]) == ["id", "name"]
    refute Enum.any?(fields, &(&1["name"] == "category_id"))
  end

  test "unknown phoenix request returns nil" do
    assert PhoenixRequests.handle("phoenix/unknown", snapshot()) == nil
  end

  defp snapshot do
    facts()
    |> Snapshot.new()
  end

  defp facts do
    {:ok, source_facts} =
      ElixirSource.facts(@source_uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true, doc: "Visible label"

        slot :inner_block, required: true do
          attr :class, :string, default: "p-2"
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
          pipe_through :browser

          live "/products/:id", ProductLive.Show, :show
        end
      end

      defmodule App.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          field :name, :string
          belongs_to :category, App.Catalog.Category
        end
      end

      defmodule AppWeb.ProductLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket), do: {:ok, socket}

        def handle_params(_params, _uri, socket), do: {:noreply, socket}

        def render(assigns), do: ~H"<div />"

        def handle_event("select-product", %{"id" => id}, socket) do
          {:noreply, assign(socket, :selected_id, id)}
        end

        def handle_info({:tick, id}, socket) do
          {:noreply, assign(socket, :tick_id, id)}
        end
      end
      """)

    source_facts ++ Template.facts(@template_uri, "<h1>Products</h1>")
  end
end
