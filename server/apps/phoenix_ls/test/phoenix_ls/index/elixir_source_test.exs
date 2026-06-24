defmodule PhoenixLS.Index.ElixirSourceTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.ElixirSource

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  test "extracts module and function facts with source ranges and provenance" do
    source = """
    defmodule AppWeb.PageLive do
      def mount(params, session, socket) do
        {:ok, socket}
      end

      defp helper(value), do: value
    end
    """

    assert {:ok, facts} = ElixirSource.facts(@uri, source, version: 8)

    assert Enum.map(facts, & &1.id) == [
             "AppWeb.PageLive",
             "AppWeb.PageLive.mount/3",
             "AppWeb.PageLive.helper/1"
           ]

    assert [module_fact, mount_fact, helper_fact] = facts

    assert module_fact.kind == :module
    assert module_fact.data == %{module: "AppWeb.PageLive"}
    assert module_fact.range == range(0, 0, 6, 3)
    assert module_fact.provenance.source == :elixir_ast
    assert module_fact.provenance.document_version == 8

    assert mount_fact.kind == :function

    assert mount_fact.data == %{
             module: "AppWeb.PageLive",
             name: "mount",
             arity: 3,
             visibility: :public
           }

    assert mount_fact.range == range(1, 2, 3, 5)

    assert helper_fact.kind == :function
    assert helper_fact.data.visibility == :private
    assert helper_fact.range == range(5, 2, 5, 31)
  end

  test "extracts nested module functions with nested module ids" do
    source = """
    defmodule AppWeb.Outer do
      defmodule Inner do
        def call(socket), do: socket
      end
    end
    """

    assert {:ok, facts} = ElixirSource.facts(@uri, source)

    assert Enum.map(facts, & &1.id) == [
             "AppWeb.Outer",
             "AppWeb.Outer.Inner",
             "AppWeb.Outer.Inner.call/1"
           ]
  end

  test "extracts public arity-one HEEx functions as component facts" do
    source = """
    defmodule AppWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button><%= @label %></button>
        \"\"\"
      end

      defp helper(assigns) do
        ~H"<span />"
      end

      def pair(assigns, opts) do
        ~H"<div />"
      end
    end
    """

    assert {:ok, facts} = ElixirSource.facts(@uri, source, version: 13)

    assert [component_fact] = Enum.filter(facts, &(&1.kind == :component))

    assert component_fact.id == "AppWeb.CoreComponents.button/1"
    assert component_fact.range == range(1, 2, 5, 5)
    assert component_fact.provenance.source == :elixir_ast
    assert component_fact.provenance.document_version == 13

    assert component_fact.data == %{
             module: "AppWeb.CoreComponents",
             name: "button",
             arity: 1,
             visibility: :public,
             type: :function
           }
  end

  test "extracts component attrs slots and slot attrs with source facts" do
    source = """
    defmodule AppWeb.CoreComponents do
      attr :label, :string, required: true
      attr :kind, :atom, default: :primary, values: [:primary, :secondary]

      slot :inner_block, required: true do
        attr :class, :string
      end

      def button(assigns) do
        ~H\"\"\"
        <button><%= render_slot(@inner_block) %></button>
        \"\"\"
      end
    end
    """

    assert {:ok, facts} = ElixirSource.facts(@uri, source, version: 21)

    component_id = "AppWeb.CoreComponents.button/1"
    assert [_component_fact] = Enum.filter(facts, &(&1.kind == :component))

    assert [label_attr, kind_attr] = Enum.filter(facts, &(&1.kind == :component_attr))

    assert label_attr.id == "#{component_id}:attr:label"
    assert label_attr.range == range(1, 2, 1, 38)
    assert label_attr.provenance.document_version == 21

    assert label_attr.data == %{
             component: component_id,
             module: "AppWeb.CoreComponents",
             component_name: "button",
             name: "label",
             type: :string,
             options: [required: true]
           }

    assert kind_attr.id == "#{component_id}:attr:kind"
    assert kind_attr.range == range(2, 2, 2, 70)

    assert kind_attr.data == %{
             component: component_id,
             module: "AppWeb.CoreComponents",
             component_name: "button",
             name: "kind",
             type: :atom,
             options: [default: :primary, values: [:primary, :secondary]]
           }

    assert [slot_fact] = Enum.filter(facts, &(&1.kind == :component_slot))

    assert slot_fact.id == "#{component_id}:slot:inner_block"
    assert slot_fact.range == range(4, 2, 6, 5)

    assert slot_fact.data == %{
             component: component_id,
             module: "AppWeb.CoreComponents",
             component_name: "button",
             name: "inner_block",
             options: [required: true]
           }

    assert [slot_attr] = Enum.filter(facts, &(&1.kind == :component_slot_attr))

    assert slot_attr.id == "#{component_id}:slot:inner_block:attr:class"
    assert slot_attr.range == range(5, 4, 5, 24)

    assert slot_attr.data == %{
             component: component_id,
             module: "AppWeb.CoreComponents",
             component_name: "button",
             slot: "inner_block",
             name: "class",
             type: :string,
             options: []
           }
  end

  test "returns parse errors without raising" do
    assert {:error, {:parse_error, _reason}} = ElixirSource.facts(@uri, "defmodule Broken do")
  end

  defp range(start_line, start_character, end_line, end_character) do
    %Range{
      start: %Position{line: start_line, character: start_character},
      end: %Position{line: end_line, character: end_character}
    }
  end
end
