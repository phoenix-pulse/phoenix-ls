defmodule PhoenixLS.Features.Completion.ComponentsTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias PhoenixLS.Features.Completion.Components
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/components/core_components.ex"

  test "completes function component tags by prefix" do
    items = complete("<.bu| />")

    assert Enum.map(items, & &1.label) == [".button"]

    assert [item] = items
    assert item.kind == CompletionItemKind.function()
    assert item.detail == "AppWeb.CoreComponents.button/1"
    assert item.insert_text == ".button"
    assert item.insert_text_format == InsertTextFormat.plain_text()

    assert item.data == %{
             "kind" => "component",
             "id" => "AppWeb.CoreComponents.button/1",
             "documentation" => "Renders a button."
           }
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
    assert item.insert_text == "CoreComponents.button"

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

  test "completes slot tags by prefix" do
    items = complete("<:in| />")

    assert Enum.map(items, & &1.label) == [":inner_block"]

    assert [item] = items
    assert item.kind == CompletionItemKind.field()
    assert item.detail == "slot :inner_block"
    assert item.insert_text == ":inner_block"

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

        def card(assigns) do
          ~H"<section />"
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
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
