defmodule PhoenixLS.HEEx.ParserTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Support.Positions
  alias GenLSP.Structures.{Position, Range}

  test "parses component tags with attrs and source ranges" do
    source = ~s(<.button label="Save" kind={:primary} />)

    assert {:ok, %Document{tags: [tag]}} = Parser.parse(source)

    assert tag.kind == :component
    assert tag.name == ".button"
    assert tag.self_closing? == true
    assert tag.name_range == range_for(source, ".button")

    assert [label, kind] = tag.attrs
    assert label.name == "label"
    assert label.value == "Save"
    assert label.value_kind == :quoted
    assert label.name_range == range_for(source, "label")

    assert kind.name == "kind"
    assert kind.value == ":primary"
    assert kind.value_kind == :expression
  end

  test "parses remote component and slot tags while ignoring closing tags" do
    source = """
    <CoreComponents.button label="Save">
      <:inner_block class="p-2" />
    </CoreComponents.button>
    """

    assert {:ok, %Document{tags: [component, slot]}} = Parser.parse(source)

    assert component.kind == :remote_component
    assert component.name == "CoreComponents.button"
    assert component.self_closing? == false
    assert Enum.map(component.attrs, & &1.name) == ["label"]

    assert slot.kind == :slot
    assert slot.name == ":inner_block"
    assert slot.self_closing? == true
    assert Enum.map(slot.attrs, & &1.name) == ["class"]
  end

  test "parses html tags and boolean attrs" do
    source = ~s(<button phx-click="save" disabled>)

    assert {:ok, %Document{tags: [tag]}} = Parser.parse(source)

    assert tag.kind == :html
    assert tag.name == "button"
    assert tag.self_closing? == false

    assert [event, disabled] = tag.attrs
    assert event.name == "phx-click"
    assert event.value == "save"
    assert event.value_kind == :quoted
    assert disabled.name == "disabled"
    assert disabled.value == nil
    assert disabled.value_kind == :boolean
  end

  test "parses HEEx expression entries separately from tags" do
    source = "<%= @name %><div id=\"profile\" />"

    assert {:ok, %Document{tags: [tag], expressions: [expression]}} = Parser.parse(source)

    assert tag.name == "div"
    assert Enum.map(tag.attrs, & &1.name) == ["id"]
    assert expression.kind == :output
    assert expression.value == "@name"
    assert expression.value_range == range_for(source, "@name")
  end

  test "recovers parsed tags when a HEEx expression is unterminated" do
    source = ~s(<button phx-click="save"></button>\n<%= @uploads.avatar)

    assert {:ok, %Document{tags: [tag], expressions: [expression]}} = Parser.parse(source)

    assert tag.name == "button"
    assert expression.kind == :output
    assert expression.value == "@uploads.avatar"
  end

  test "returns parser errors for unterminated tags" do
    assert Parser.parse("<.button label=\"Save\"") == {:error, :unterminated_tag}
  end

  defp range_for(source, text) do
    {offset, length} = :binary.match(source, text)
    {:ok, start_position} = Positions.offset_to_lsp_position(source, offset)
    {:ok, end_position} = Positions.offset_to_lsp_position(source, offset + length)

    %Range{start: position(start_position), end: position(end_position)}
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end
end
