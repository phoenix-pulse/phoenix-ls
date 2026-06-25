defmodule PhoenixLS.LSP.CompletionTransportTest do
  use ExUnit.Case, async: false

  import GenLSP.Test, only: [assert_result: 3]
  import PhoenixLS.Support.LSPConfigHelpers, only: [companion_config: 0]

  alias PhoenixLS.LSP.Server
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI

  test "GenLSP transport returns component completions from open project indexes", context do
    attach_indexer()

    root = fixture_project(context, "completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.bu| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri)
    assert_indexed(page_uri)

    assert_core_button_completion(test_client, heex_uri, position, 2)
  end

  test "GenLSP transport keeps component completions after reopening a HEEx document", context do
    attach_indexer()

    root = fixture_project(context, "reopened_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.bu| />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri)
    assert_indexed(page_uri)
    assert_indexed(heex_uri)

    assert_core_button_completion(test_client, heex_uri, position, 31)

    close_document(test_client, heex_uri)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(heex_uri)

    assert_core_button_completion(test_client, heex_uri, position, 32)
  end

  test "GenLSP transport keeps component completions in companion mode", context do
    attach_indexer()

    root = fixture_project(context, "companion_component_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.bu| />")

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri)
    assert_indexed(page_uri)

    GenLSP.Test.request(test_client, %{
      id: 25,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      25,
      [
        %{
          "data" => %{"id" => "AppWeb.CoreComponents.button/1", "kind" => "component"},
          "detail" => "AppWeb.CoreComponents.button/1",
          "insertText" => ".button",
          "insertTextFormat" => 1,
          "kind" => 3,
          "label" => ".button"
        }
      ],
      500
    )
  end

  test "GenLSP transport scopes slot completions to the active component", context do
    attach_indexer()

    root = fixture_project(context, "slot_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.card><:| /></.card>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source_with_slots())
    page_uri = open_page_module(test_client, root)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(component_uri)
    assert_indexed(page_uri)

    GenLSP.Test.request(test_client, %{
      id: 22,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 22,
                     "result" => [
                       %{
                         "data" => %{
                           "id" => "AppWeb.CoreComponents.card/1:slot:footer",
                           "kind" => "component_slot"
                         },
                         "detail" => "slot :footer",
                         "insertText" => ":footer",
                         "label" => ":footer"
                       }
                     ]
                   },
                   500
  end

  test "GenLSP transport returns an empty completion list for unsupported contexts", context do
    root = fixture_project(context, "empty_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<p>Hello |world</p>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(2, [], 500)
  end

  test "GenLSP transport completes built-in Phoenix component attrs in HEEx", context do
    root = fixture_project(context, "builtin_link_attr_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.link |></.link>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 26,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_receive %{"jsonrpc" => "2.0", "id" => 26, "result" => result}, 500

    labels = Enum.map(result, & &1["label"])

    assert "href" in labels
    assert "navigate" in labels
    assert "patch" in labels
    assert "class" in labels
    assert "phx-click" in labels
  end

  test "GenLSP transport completes built-in Phoenix component attrs in H sigils", context do
    root = fixture_project(context, "builtin_link_attr_h_sigils_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page_live.ex"))

    {elixir_source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H\"\"\"
          <.link |></.link>
          \"\"\"
        end
      end
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, elixir_uri, "elixir", elixir_source)

    GenLSP.Test.request(test_client, %{
      id: 27,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: elixir_uri},
        position: position
      }
    })

    assert_receive %{"jsonrpc" => "2.0", "id" => 27, "result" => result}, 500

    labels = Enum.map(result, & &1["label"])

    assert "href" in labels
    assert "navigate" in labels
    assert "patch" in labels
    assert "class" in labels
    assert "phx-click" in labels
  end

  test "GenLSP transport completes same-module events in H sigils", context do
    attach_indexer()

    root = fixture_project(context, "h_sigils_event_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page_live.ex"))

    {elixir_source, position} =
      source_and_position("""
      defmodule AppWeb.PageLive do
        use Phoenix.LiveView

        def handle_event("close-product", _params, socket) do
          {:noreply, socket}
        end

        def render(assigns) do
          ~H\"\"\"
          <button phx-click="clo|">Close</button>
          \"\"\"
        end
      end
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, elixir_uri, "elixir", elixir_source)
    assert_indexed(elixir_uri)

    GenLSP.Test.request(test_client, %{
      id: 28,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: elixir_uri},
        position: position
      }
    })

    assert_receive %{"jsonrpc" => "2.0", "id" => 28, "result" => result}, 500

    assert Enum.map(result, & &1["label"]) == ["close-product"]
  end

  test "GenLSP transport completes component attrs and slots as assigns in H sigils", context do
    attach_indexer()

    root = fixture_project(context, "component_assign_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    elixir_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/admin_components.ex"))

    {elixir_source, position} =
      source_and_position("""
      defmodule AppWeb.AdminComponents do
        use Phoenix.Component

        attr :title, :string, required: true
        attr :value, :any, required: true
        attr :tone, :string, default: "neutral"
        slot :inner_block

        def metric_card(assigns) do
          ~H\"\"\"
          {@|}
          \"\"\"
        end

        attr :entries, :list, default: []

        def audit_timeline(assigns) do
          ~H\"\"\"
          {@entries}
          \"\"\"
        end
      end
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, elixir_uri, "elixir", elixir_source)
    assert_indexed(elixir_uri)

    GenLSP.Test.request(test_client, %{
      id: 30,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: elixir_uri},
        position: position
      }
    })

    assert_receive %{"jsonrpc" => "2.0", "id" => 30, "result" => result}, 500

    labels = Enum.map(result, & &1["label"])

    assert "@inner_block" in labels
    assert "@title" in labels
    assert "@tone" in labels
    assert "@value" in labels
    refute "@entries" in labels
  end

  test "GenLSP transport returns route completions from indexed router facts", context do
    attach_indexer()

    root = fixture_project(context, "route_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.link navigate={~p\"/prod|\"} />")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(router_uri)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      2,
      [
        %{
          "data" => %{
            "id" => "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show",
            "kind" => "route"
          },
          "detail" => "live AppWeb.ProductLive.Show :show",
          "insertText" => "/products/:id",
          "insertTextFormat" => 1,
          "kind" => 18,
          "label" => "/products/:id"
        }
      ],
      500
    )
  end

  test "GenLSP transport omits generic Elixir fallback completions in companion mode",
       context do
    root = fixture_project(context, "companion_generic_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<p>{to_s|}</p>")

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)

    GenLSP.Test.request(test_client, %{
      id: 23,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(23, [], 500)
  end

  test "GenLSP transport keeps route completions in companion mode", context do
    attach_indexer()

    root = fixture_project(context, "companion_route_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))
    heex_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.html.heex"))

    {heex_source, position} = source_and_position("<.link navigate={~p\"/prod|\"} />")

    test_server = GenLSP.Test.server(Server, init_args: [server_config: companion_config()])
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(router_uri)

    GenLSP.Test.request(test_client, %{
      id: 24,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      24,
      [
        %{
          "data" => %{
            "id" => "AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show",
            "kind" => "route"
          },
          "detail" => "live AppWeb.ProductLive.Show :show",
          "insertText" => "/products/:id",
          "insertTextFormat" => 1,
          "kind" => 18,
          "label" => "/products/:id"
        }
      ],
      500
    )
  end

  test "GenLSP transport returns route helper completions in Elixir documents", context do
    attach_indexer()

    root = fixture_project(context, "route_helper_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    router_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/router.ex"))
    elixir_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page_live.ex"))

    {elixir_source, position} = source_and_position("Routes.us|")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, router_uri, "elixir", router_source())
    assert_indexed(router_uri)
    open_document(test_client, elixir_uri, "elixir", elixir_source)

    GenLSP.Test.request(test_client, %{
      id: 2,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: elixir_uri},
        position: position
      }
    })

    assert_result(
      2,
      [
        %{
          "data" => %{"helper" => "user_path", "kind" => "route_helper"},
          "detail" => "Routes.user_path",
          "insertText" => "user_path(${1:conn_or_socket}, :${2|index,show|}, ${3:id})",
          "insertTextFormat" => 2,
          "kind" => 3,
          "label" => "user_path"
        },
        %{
          "data" => %{"helper" => "user_url", "kind" => "route_helper"},
          "detail" => "Routes.user_url",
          "insertText" => "user_url(${1:conn_or_socket}, :${2|index,show|}, ${3:id})",
          "insertTextFormat" => 2,
          "kind" => 3,
          "label" => "user_url"
        }
      ],
      500
    )
  end

  test "GenLSP transport scopes LiveView event completions to the template module", context do
    attach_indexer()

    root = fixture_project(context, "event_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    admin_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/admin/product_live.ex"))

    product_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.ex"))

    heex_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.html.heex"))

    {heex_source, position} = source_and_position(~s(<button phx-click="save-|">Save</button>))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)

    open_document(
      test_client,
      admin_uri,
      "elixir",
      live_view_source("AppWeb.Admin.ProductLive", "save-admin")
    )

    open_document(
      test_client,
      product_uri,
      "elixir",
      live_view_source("AppWeb.ProductLive", "save-product")
    )

    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(admin_uri)
    assert_indexed(product_uri)
    assert_indexed(heex_uri)

    GenLSP.Test.request(test_client, %{
      id: 3,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      3,
      [
        %{
          "data" => %{
            "id" => "AppWeb.ProductLive:event:save-product",
            "kind" => "live_event"
          },
          "detail" => "handle_event(\"save-product\", ...)",
          "insertText" => "save-product",
          "insertTextFormat" => 1,
          "kind" => 23,
          "label" => "save-product"
        }
      ],
      500
    )
  end

  test "GenLSP transport scopes LiveView assign completions to the template module", context do
    attach_indexer()

    root = fixture_project(context, "assign_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    admin_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/admin/product_live.ex"))

    product_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.ex"))

    heex_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.html.heex"))

    {heex_source, position} = source_and_position("<p>{@sele|}</p>")

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)

    open_document(
      test_client,
      admin_uri,
      "elixir",
      live_view_assign_source("AppWeb.Admin.ProductLive")
    )

    open_document(
      test_client,
      product_uri,
      "elixir",
      live_view_assign_source("AppWeb.ProductLive")
    )

    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(admin_uri)
    assert_indexed(product_uri)
    assert_indexed(heex_uri)

    GenLSP.Test.request(test_client, %{
      id: 4,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      4,
      [
        %{
          "data" => %{
            "id" => "AppWeb.ProductLive:assign:selected_id",
            "kind" => "assign"
          },
          "detail" => "assign @selected_id",
          "insertText" => "@selected_id",
          "insertTextFormat" => 1,
          "kind" => 6,
          "label" => "@selected_id"
        }
      ],
      500
    )
  end

  test "GenLSP transport completes form fields from to_form bindings", context do
    attach_indexer()

    root = fixture_project(context, "form_field_completion_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    schema_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app/catalog/product.ex"))

    heex_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/product_live.html.heex"))

    {heex_source, position} =
      source_and_position("""
      <.form :let={f} for={Phoenix.Component.to_form(@product)}>
        <.input field={f[:na|]} />
      </.form>
      """)

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, schema_uri, "elixir", product_schema_source())
    open_document(test_client, heex_uri, "phoenix-heex", heex_source)
    assert_indexed(schema_uri)
    assert_indexed(heex_uri)

    GenLSP.Test.request(test_client, %{
      id: 29,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: heex_uri},
        position: position
      }
    })

    assert_result(
      29,
      [
        %{
          "data" => %{
            "id" => "App.Catalog.Product:schema:products:field:name",
            "kind" => "schema_field"
          },
          "detail" => "field :name, :string",
          "insertText" => "name",
          "insertTextFormat" => 1,
          "kind" => 5,
          "label" => "name"
        }
      ],
      500
    )
  end

  test "GenLSP transport resolves completion item documentation" do
    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    GenLSP.Test.request(test_client, %{
      id: 9,
      jsonrpc: "2.0",
      method: "completionItem/resolve",
      params: %{
        label: "label",
        detail: "attr :label, :string",
        data: %{
          "kind" => "component_attr",
          "id" => "AppWeb.CoreComponents.button/1:attr:label",
          "documentation" => "Visible label"
        }
      }
    })

    assert_result(
      9,
      %{
        "data" => %{
          "documentation" => "Visible label",
          "id" => "AppWeb.CoreComponents.button/1:attr:label",
          "kind" => "component_attr"
        },
        "detail" => "attr :label, :string",
        "documentation" => "Visible label",
        "label" => "label"
      },
      500
    )
  end

  test "GenLSP transport resolves completion items with indexed source context", context do
    attach_indexer()

    root = fixture_project(context, "resolve_source_context_project")
    root_uri = SupportURI.path_to_file_uri!(root)

    component_uri =
      SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/components/core_components.ex"))

    test_server = GenLSP.Test.server(Server)
    test_client = GenLSP.Test.client(test_server)

    initialize(test_client, root_uri)
    open_document(test_client, component_uri, "elixir", component_source())
    assert_indexed(component_uri)

    GenLSP.Test.request(test_client, %{
      id: 10,
      jsonrpc: "2.0",
      method: "completionItem/resolve",
      params: %{
        label: ".button",
        detail: "AppWeb.CoreComponents.button/1",
        data: %{
          "kind" => "component",
          "id" => "AppWeb.CoreComponents.button/1"
        }
      }
    })

    assert_receive %{
                     "jsonrpc" => "2.0",
                     "id" => 10,
                     "result" => %{
                       "documentation" => documentation
                     }
                   },
                   500

    assert String.contains?(documentation, "function component")
    assert String.contains?(documentation, "Source")
    assert String.contains?(documentation, SupportURI.file_uri_to_path!(component_uri))
    assert String.contains?(documentation, "AppWeb.CoreComponents")
  end

  def handle_indexer_event(event, measurements, metadata, parent) do
    send(parent, {:indexer_event, event, measurements, metadata})
  end

  defp attach_indexer do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:phoenix_ls, :indexer, :document],
      &__MODULE__.handle_indexer_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_indexed(uri) do
    assert_receive {:indexer_event, [:phoenix_ls, :indexer, :document], _measurements,
                    %{uri: ^uri, result: :ok}},
                   500
  end

  defp initialize(test_client, root_uri) do
    version = PhoenixLS.version()

    GenLSP.Test.request(test_client, %{
      id: 1,
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        capabilities: %{},
        processId: nil,
        rootUri: root_uri
      }
    })

    assert_result(
      1,
      %{
        "capabilities" => %{
          "completionProvider" => %{
            "resolveProvider" => true,
            "triggerCharacters" => ["<", " ", "-", ":", "\"", "'", "=", "{", ".", "#", "@", "/"]
          },
          "experimental" => nil,
          "textDocumentSync" => %{
            "openClose" => true,
            "change" => 1
          },
          "workspace" => %{
            "workspaceFolders" => %{
              "supported" => true,
              "changeNotifications" => true
            }
          }
        },
        "serverInfo" => %{
          "name" => "PhoenixLS",
          "version" => ^version
        }
      },
      1_500
    )
  end

  defp open_document(test_client, uri, language_id, text) do
    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: %{
        textDocument: %{
          uri: uri,
          languageId: language_id,
          version: 1,
          text: text
        }
      }
    })
  end

  defp close_document(test_client, uri) do
    GenLSP.Test.notify(test_client, %{
      jsonrpc: "2.0",
      method: "textDocument/didClose",
      params: %{
        textDocument: %{uri: uri}
      }
    })
  end

  defp assert_core_button_completion(test_client, uri, position, id) do
    GenLSP.Test.request(test_client, %{
      id: id,
      jsonrpc: "2.0",
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: uri},
        position: position
      }
    })

    assert_result(
      ^id,
      [
        %{
          "data" => %{"id" => "AppWeb.CoreComponents.button/1", "kind" => "component"},
          "detail" => "AppWeb.CoreComponents.button/1",
          "insertText" => ".button",
          "insertTextFormat" => 1,
          "kind" => 3,
          "label" => ".button"
        }
      ],
      500
    )
  end

  defp open_page_module(test_client, root) do
    page_uri = SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page.ex"))

    open_document(test_client, page_uri, "elixir", """
    defmodule AppWeb.Page do
      import AppWeb.CoreComponents
    end
    """)

    page_uri
  end

  defp component_source do
    """
    defmodule AppWeb.CoreComponents do
      attr :label, :string

      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
      end
    end
    """
  end

  defp component_source_with_slots do
    """
    defmodule AppWeb.CoreComponents do
      slot :inner_block

      def button(assigns) do
        ~H\"\"\"
        <button><%= render_slot(@inner_block) %></button>
        \"\"\"
      end

      slot :footer

      def card(assigns) do
        ~H\"\"\"
        <section><%= render_slot(@footer) %></section>
        \"\"\"
      end
    end
    """
  end

  defp router_source do
    """
    defmodule AppWeb.Router do
      use Phoenix.Router

      scope "/", AppWeb do
        get "/users", UserController, :index
        get "/users/:id", UserController, :show
        live "/products/:id", ProductLive.Show, :show
      end
    end
    """
  end

  defp live_view_source(module, event) do
    """
    defmodule #{module} do
      use Phoenix.LiveView

      def handle_event("#{event}", _params, socket) do
        {:noreply, socket}
      end
    end
    """
  end

  defp live_view_assign_source(module) do
    """
    defmodule #{module} do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :selected_id, "1")}
      end
    end
    """
  end

  defp product_schema_source do
    """
    defmodule App.Catalog.Product do
      use Ecto.Schema

      schema "products" do
        field :name, :string
      end
    end
    """
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, %{line: position.line, character: position.character}}
  end

  defp marker_offset!(marked_source) do
    marked_source
    |> :binary.matches("|")
    |> case do
      [{offset, 1}] -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(Path.join(root, "lib/app_web/components"))
    File.mkdir_p!(Path.join(root, "lib/app_web/live"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule CompletionFixture.MixProject do
      use Mix.Project

      def project do
        [app: :completion_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)

    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_completion_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
