defmodule PhoenixLS.Features.Completion.ComponentsTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias PhoenixLS.Features.Completion.Components
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/components/core_components.ex"
  @template_uri "file:///tmp/app/lib/app_web/controllers/page_html/index.html.heex"

  test "completes function component tags by prefix" do
    items = complete("<.bu| />")

    assert Enum.map(items, & &1.label) == [".button"]

    assert [item] = items
    assert item.kind == CompletionItemKind.function()
    assert item.detail == "AppWeb.CoreComponents.button/1"
    assert item.insert_text == ".button label={${1:value}}"
    assert item.insert_text_format == InsertTextFormat.snippet()

    assert item.data == %{
             "kind" => "component",
             "id" => "AppWeb.CoreComponents.button/1",
             "documentation" => "Renders a button."
           }
  end

  test "component tag completions include required attr snippets" do
    items = complete("<.bu| />")

    assert [item] = items
    assert item.label == ".button"
    assert item.insert_text == ".button label={${1:value}}"
    assert item.insert_text_format == InsertTextFormat.snippet()
  end

  test "completes component attrs for a local function component tag" do
    items = complete("<.button |>")

    assert Enum.map(items, & &1.label) == ["label", "kind"]

    assert [label_item, kind_item] = items
    assert label_item.kind == CompletionItemKind.property()
    assert label_item.detail == "attr :label, :string"
    assert label_item.insert_text == "label"

    assert label_item.data == %{
             "kind" => "component_attr",
             "id" => "AppWeb.CoreComponents.button/1:attr:label"
           }

    assert kind_item.detail == "attr :kind, :atom"
  end

  test "completes remote component tags through aliases" do
    items = complete("<CoreComponents.bu| />")

    assert Enum.map(items, & &1.label) == ["CoreComponents.button"]

    assert [item] = items
    assert item.kind == CompletionItemKind.function()
    assert item.detail == "AppWeb.CoreComponents.button/1"
    assert item.insert_text == "CoreComponents.button label={${1:value}}"
    assert item.insert_text_format == InsertTextFormat.snippet()

    assert item.data == %{
             "kind" => "component",
             "id" => "AppWeb.CoreComponents.button/1",
             "documentation" => "Renders a button."
           }
  end

  test "completes remote component attrs through aliases" do
    items = complete("<CoreComponents.button |> ")

    assert Enum.map(items, & &1.label) == ["label", "kind"]
  end

  test "source-aware local component completions require availability in the template module" do
    assert complete_source(
             @template_uri,
             "<.bu| />",
             component_facts() ++ template_facts("<.bu />")
           ) == []

    items =
      complete_source(
        @template_uri,
        "<.bu| />",
        component_facts() ++ template_facts("<.bu />") ++ imported_html_facts()
      )

    assert Enum.map(items, & &1.label) == [".button"]

    macro_items =
      complete_source(
        @template_uri,
        "<.bu| />",
        component_facts() ++
          template_facts("<.bu />") ++
          page_html_uses_web_macro_facts() ++ web_macro_import_facts()
      )

    assert Enum.map(macro_items, & &1.label) == [".button"]
  end

  test "source-aware local component attr completions require availability in the template module" do
    assert complete_source(
             @template_uri,
             "<.button |>",
             component_facts() ++ template_facts("<.button >")
           ) == []

    items =
      complete_source(
        @template_uri,
        "<.button |>",
        component_facts() ++ template_facts("<.button >") ++ imported_html_facts()
      )

    assert Enum.map(items, & &1.label) == ["label", "kind"]

    macro_items =
      complete_source(
        @template_uri,
        "<.button |>",
        component_facts() ++
          template_facts("<.button >") ++
          page_html_uses_web_macro_facts() ++
          web_macro_import_facts()
      )

    assert Enum.map(macro_items, & &1.label) == ["label", "kind"]
  end

  test "completes slot tags by prefix" do
    items = complete("<:in| />")

    assert Enum.map(items, & &1.label) == [":inner_block"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "slot :inner_block"
    assert item.insert_text =~ ":inner_block"
    assert item.insert_text_format == InsertTextFormat.snippet()

    assert item.data == %{
             "kind" => "component_slot",
             "id" => "AppWeb.CoreComponents.button/1:slot:inner_block"
           }
  end

  test "completes slot attrs for a slot tag" do
    items = complete("<:inner_block |>")

    assert Enum.map(items, & &1.label) == ["class"]

    assert [item] = items
    assert item.kind == CompletionItemKind.property()
    assert item.detail == "slot attr :class, :string"
    assert item.insert_text == "class"

    assert item.data == %{
             "kind" => "component_slot_attr",
             "id" => "AppWeb.CoreComponents.button/1:slot:inner_block:attr:class"
           }
  end

  test "source-aware slot completions are scoped to the active component" do
    assert complete_source("<.button><:| /></.button>") |> Enum.map(& &1.label) == [
             ":inner_block"
           ]

    assert complete_source("<.card><:| /></.card>") |> Enum.map(& &1.label) == [":footer"]
  end

  test "source-aware slot completions insert snippets for declared slots" do
    assert [item] = complete_source("<.list><:it| /></.list>")

    assert item.label == ":item"
    assert item.insert_text =~ ":item"
    assert item.insert_text =~ "role={${1:value}}"
    assert item.insert_text_format == InsertTextFormat.snippet()
  end

  test "source-aware slot completions do not fabricate implicit inner_block slots" do
    assert complete_source("<.empty><:| /></.empty>") == []
  end

  test "source-aware slot completions are not offered outside component blocks" do
    assert complete_source("<:| />") == []
  end

  test "source-aware slot attr completions are scoped to the active component slot" do
    button_items = complete_source("<.button><:inner_block | /></.button>")
    card_items = complete_source("<.card><:footer | /></.card>")

    assert Enum.map(button_items, & &1.label) == ["class"]
    assert Enum.map(card_items, & &1.label) == ["role"]
  end

  test "does not complete outside supported component contexts" do
    assert complete("<p>Hello |world</p>") == []
    assert complete("<p>{@na|me}</p>") == []
    assert complete("</.but|ton>") == []
  end

  defp complete(marked_source) do
    {source, position} = source_and_position(marked_source)
    {:ok, context} = CursorContext.at(source, position)

    Components.complete(context, component_facts())
  end

  defp complete_source(marked_source) do
    {source, position} = source_and_position(marked_source)

    Components.complete(source, position, component_facts())
  end

  defp complete_source(uri, marked_source, facts) do
    {source, position} = source_and_position(marked_source)
    {:ok, context} = CursorContext.at(source, position)

    Components.complete(uri, source, position, context, facts)
  end

  defp component_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true
        attr :kind, :atom, default: :primary

        slot :inner_block do
          attr :class, :string
        end

        @doc "Renders a button."
        def button(assigns) do
          ~H\"\"\"
          <button><%= render_slot(@inner_block) %></button>
          \"\"\"
        end

        slot :footer do
          attr :role, :string
        end

        def card(assigns) do
          ~H\"\"\"
          <section><%= render_slot(@footer) %></section>
          \"\"\"
        end

        slot :item, required: true do
          attr :role, :string, required: true
        end

        def list(assigns) do
          ~H\"\"\"
          <ul><%= render_slot(@item) %></ul>
          \"\"\"
        end

        def empty(assigns) do
          ~H\"\"\"
          <div>{render_slot(@inner_block)}</div>
          \"\"\"
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp template_facts(source), do: Template.facts(@template_uri, source)

  defp imported_html_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        import AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp page_html_uses_web_macro_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/controllers/page_html.ex", """
      defmodule AppWeb.PageHTML do
        use AppWeb, :html
      end
      """)

    facts
  end

  defp web_macro_import_facts do
    {:ok, facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web.ex", """
      defmodule AppWeb do
        def html do
          quote do
            import AppWeb.CoreComponents
          end
        end
      end
      """)

    facts
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, position}
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
end
