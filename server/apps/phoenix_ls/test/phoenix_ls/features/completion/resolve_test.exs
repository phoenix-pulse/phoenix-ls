defmodule PhoenixLS.Features.Completion.ResolveTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.Resolve
  alias PhoenixLS.Index.ElixirSource

  @uri "file:///tmp/app/lib/app_web/components/core_components.ex"

  test "adds documentation for route helper completion payloads" do
    item = %CompletionItem{
      label: "user_path",
      detail: "Routes.user_path",
      data: %{"kind" => "route_helper", "helper" => "user_path"}
    }

    assert %{documentation: documentation} = Resolve.resolve(item)
    assert documentation =~ "Routes.user_path"
    assert documentation =~ "router"
  end

  test "keeps embedded completion documentation when present" do
    item = %CompletionItem{
      label: ".button",
      detail: "AppWeb.CoreComponents.button/1",
      data: %{
        "kind" => "component",
        "id" => "AppWeb.CoreComponents.button/1",
        "documentation" => "Renders a button."
      }
    }

    assert %{documentation: "Renders a button."} = Resolve.resolve(item)
  end

  test "adds source context for indexed fact completion payloads" do
    item = %CompletionItem{
      label: ".button",
      detail: "AppWeb.CoreComponents.button/1",
      data: %{"kind" => "component", "id" => "AppWeb.CoreComponents.button/1"}
    }

    fact =
      PhoenixLS.Index.Fact.new!(
        kind: :component,
        id: "AppWeb.CoreComponents.button/1",
        uri: "file:///tmp/app/lib/app_web/components/core_components.ex",
        range: %GenLSP.Structures.Range{
          start: %GenLSP.Structures.Position{line: 10, character: 2},
          end: %GenLSP.Structures.Position{line: 10, character: 12}
        },
        provenance: %{source: :test},
        data: %{module: "AppWeb.CoreComponents", name: "button"}
      )

    assert %{documentation: documentation} = Resolve.resolve(item, [fact])

    assert documentation =~ "AppWeb.CoreComponents.button/1"
    assert documentation =~ "function component"
    assert documentation =~ "Source"
    assert documentation =~ "/tmp/app/lib/app_web/components/core_components.ex:11:3"
    assert documentation =~ "AppWeb.CoreComponents"
  end

  test "resolves slot completions with parent component docs attrs and example" do
    item = %CompletionItem{
      label: ":item",
      detail: "slot :item",
      data: %{
        "kind" => "component_slot",
        "id" => "AppWeb.CoreComponents.list/1:slot:item"
      }
    }

    assert %{documentation: documentation} = Resolve.resolve(item, slot_component_facts())

    assert documentation =~ "slot :item"
    assert documentation =~ "component AppWeb.CoreComponents.list/1"
    assert documentation =~ "required: true"
    assert documentation =~ "List row"
    assert documentation =~ "slot attr :role, :string"
    assert documentation =~ "Required item role"
    assert documentation =~ "Example"
    assert documentation =~ "<:item"
  end

  test "resolves built-in Phoenix component completions with attr docs" do
    cases = [
      {".link", "Phoenix.Component.link/1",
       ["Renders a link", "attr :navigate, :string", "attr :replace, :boolean"]},
      {".form", "Phoenix.Component.form/1",
       ["Renders a form tag", "attr :for, :any", "attr :method, :string"]},
      {".live_component", "Phoenix.Component.live_component/1",
       ["Renders a stateful LiveComponent", "attr :module, :atom", "attr :id, :string"]}
    ]

    for {label, id, expected_fragments} <- cases do
      item = %CompletionItem{
        label: label,
        detail: id,
        data: %{"kind" => "phoenix_component", "id" => id}
      }

      assert %{documentation: documentation} = Resolve.resolve(item)

      for expected <- expected_fragments do
        assert documentation =~ expected
      end
    end
  end

  cases = [
    {"route", "/users", "GET AppWeb.UserController :index",
     %{"kind" => "route", "id" => "route:/users"},
     ["GET AppWeb.UserController :index", "verified Phoenix route"]},
    {"asset", "/images/logo.svg", "image asset - 1.0 KB",
     %{"kind" => "asset", "id" => "/images/logo.svg"}, ["image asset - 1.0 KB", "static asset"]},
    {"template", ":index", "Template file: index.html.heex",
     %{
       "kind" => "template",
       "template" => "index",
       "format" => "html",
       "uri" => "file:///app/index.html.heex"
     }, ["Template file: index.html.heex", "controller render template"]},
    {"component", ".button", "AppWeb.CoreComponents.button/1",
     %{"kind" => "component", "id" => "AppWeb.CoreComponents.button/1"},
     ["AppWeb.CoreComponents.button/1", "function component"]},
    {"component attr", "label", "attr :label, :string",
     %{"kind" => "component_attr", "id" => "AppWeb.CoreComponents.button/1:attr:label"},
     ["attr :label, :string", "component attribute"]},
    {"component slot", ":inner_block", "slot :inner_block",
     %{"kind" => "component_slot", "id" => "AppWeb.CoreComponents.button/1:slot:inner_block"},
     ["slot :inner_block", "component slot"]},
    {"component slot attr", "class", "slot attr :class, :string",
     %{
       "kind" => "component_slot_attr",
       "id" => "AppWeb.CoreComponents.button/1:slot:inner_block:attr:class"
     }, ["slot attr :class, :string", "slot attribute"]},
    {"schema field", "name", "field :name, :string",
     %{"kind" => "schema_field", "id" => "App.Catalog.Product:field:name"},
     ["field :name, :string", "Ecto schema field"]},
    {"schema association", "category", "belongs_to :category, App.Catalog.Category",
     %{"kind" => "schema_association", "id" => "App.Catalog.Product:association:category"},
     ["belongs_to :category, App.Catalog.Category", "Ecto schema association"]},
    {"assign", "@product", "assign @product", %{"kind" => "assign", "id" => "assign:product"},
     ["assign @product", "LiveView assign"]},
    {"live event", "save", ~s[handle_event("save", ...)],
     %{"kind" => "live_event", "id" => "AppWeb.ProductLive:handle_event:save"},
     [~s[handle_event("save", ...)], "LiveView event handler"]},
    {"LiveView JS command", "JS.show", "Show elements",
     %{"kind" => "live_view_js_command", "name" => "show"},
     ["Show elements", "Phoenix.LiveView.JS command"]},
    {"HTML attr", "src", "Image source URL",
     %{"kind" => "html_attr", "tag" => "img", "name" => "src"},
     ["Image source URL", "HTML attribute"]},
    {"HTML attr value", "email", "type value for <input>",
     %{"kind" => "html_attr_value", "tag" => "input", "attribute" => "type", "value" => "email"},
     ["type value for <input>", "HTML attribute value"]},
    {"HEEx special attr", ":if", "Conditional rendering",
     %{"kind" => "heex_special_attr", "id" => ":if"},
     ["Conditional rendering", "HEEx special attribute"]},
    {"Phoenix attr", "phx-click", "Click event", %{"kind" => "phoenix_attr", "id" => "phx-click"},
     ["Click event", "Phoenix attribute"]},
    {"HTML tag", "div", "HTML <div>", %{"kind" => "html_tag", "id" => "div"},
     ["HTML <div>", "HTML tag"]},
    {"shortcut snippet", "@click", "Phoenix event shortcut",
     %{"kind" => "shortcut_snippet", "id" => "@click"},
     ["Phoenix event shortcut", "shortcut snippet"]},
    {"phx value field", "phx-value-id", "From product: :integer",
     %{"kind" => "phx_value_field", "id" => "App.Catalog.Product:field:id"},
     ["From product: :integer", "`phx-value-*` field"]},
    {"Elixir fallback", "inspect", "Kernel.inspect/1",
     %{"kind" => "elixir_fallback", "id" => "inspect"},
     ["Kernel.inspect/1", "Elixir fallback completion"]}
  ]

  for {name, label, detail, data, expected_fragments} <- cases do
    test "adds documentation for #{name} completion payloads" do
      item = %CompletionItem{
        label: unquote(label),
        detail: unquote(detail),
        data: unquote(Macro.escape(data))
      }

      assert %{documentation: documentation} = Resolve.resolve(item)

      for expected <- unquote(expected_fragments) do
        assert documentation =~ expected
      end
    end
  end

  defp slot_component_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        slot :item, required: true, doc: "List row" do
          attr :role, :string, required: true, doc: "Required item role"
        end

        def list(assigns) do
          ~H\"\"\"
          <ul><%= render_slot(@item) %></ul>
          \"\"\"
        end
      end
      """)

    facts
  end
end
