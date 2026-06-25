defmodule PhoenixLS.Features.PhoenixRequestsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Features.PhoenixRequests
  alias PhoenixLS.Index.ElixirSource
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
               "fieldsCount" => 1,
               "associationsCount" => 1,
               "fields" => [
                 %{
                   "name" => "name",
                   "type" => "string",
                   "elixirType" => ":string",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _field_line, "character" => 4}
                 }
               ],
               "associations" => [
                 %{
                   "name" => "category",
                   "fieldName" => "category",
                   "schema" => "App.Catalog.Category",
                   "targetModule" => "App.Catalog.Category",
                   "type" => "belongs_to",
                   "cardinality" => "many_to_one",
                   "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
                   "location" => %{"line" => _association_line, "character" => 4}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listSchemas", facts())

    assert line > 0
  end

  test "lists components with attrs, slots, and slot attrs" do
    assert [
             %{
               "name" => "button",
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
                   "rawType" => ":string"
                 }
               ],
               "slots" => [
                 %{
                   "name" => "inner_block",
                   "required" => true,
                   "attributes" => [
                     %{
                       "name" => "class",
                       "type" => "string",
                       "required" => false,
                       "default" => "\"p-2\"",
                       "rawType" => ":string"
                     }
                   ]
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listComponents", facts())
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
               "scopePath" => "/",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 4}
             }
           ] = PhoenixRequests.handle("phoenix/listRoutes", facts())
  end

  test "lists templates" do
    assert [
             %{
               "name" => "index.html",
               "format" => "heex",
               "filePath" => "/tmp/app/lib/app_web/controllers/page_html/index.html.heex",
               "location" => %{"line" => 0, "character" => 0},
               "module" => ""
             }
           ] = PhoenixRequests.handle("phoenix/listTemplates", facts())
  end

  test "lists LiveView events" do
    assert [
             %{
               "name" => "select-product",
               "type" => "handle_event",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "location" => %{"line" => _line, "character" => 2}
             }
           ] = PhoenixRequests.handle("phoenix/listEvents", facts())
  end

  test "lists LiveView modules with functions" do
    assert [
             %{
               "module" => "AppWeb.ProductLive",
               "filePath" => "/tmp/app/lib/app_web/live/page_live.ex",
               "functions" => [
                 %{
                   "name" => "handle_event",
                   "type" => "handle_event",
                   "eventName" => "select-product",
                   "location" => %{"line" => _line, "character" => 2}
                 }
               ]
             }
           ] = PhoenixRequests.handle("phoenix/listLiveView", facts())
  end

  test "unknown phoenix request returns nil" do
    assert PhoenixRequests.handle("phoenix/unknown", facts()) == nil
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

        def handle_event("select-product", %{"id" => id}, socket) do
          {:noreply, assign(socket, :selected_id, id)}
        end
      end
      """)

    source_facts ++ Template.facts(@template_uri, "<h1>Products</h1>")
  end
end
