defmodule PhoenixLS.Features.PhoenixRequestsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Features.PhoenixRequests
  alias PhoenixLS.Index.{ElixirSource, Snapshot}
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
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 4}
             }
           ] = PhoenixRequests.handle("phoenix/listRoutes", snapshot())
  end

  test "lists templates" do
    assert [
             %{
               "name" => "index.html",
               "format" => "heex",
               "filePath" => "/tmp/app/lib/app_web/controllers/page_html/index.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => "AppWeb.PageHTML"
             }
           ] = PhoenixRequests.handle("phoenix/listTemplates", snapshot())
  end

  test "lists LiveView events" do
    assert [
             %{
               "name" => "select-product",
               "type" => "handle_event",
               "module" => "AppWeb.ProductLive",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 2}
             }
           ] = PhoenixRequests.handle("phoenix/listEvents", snapshot())
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
