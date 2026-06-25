defmodule PhoenixLS.Features.Completion.ResolveTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.Resolve

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
end
