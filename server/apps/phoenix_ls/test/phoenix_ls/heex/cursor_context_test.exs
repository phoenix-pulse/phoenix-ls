defmodule PhoenixLS.HEEx.CursorContextTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Support.Positions

  test "classifies text outside tags and expressions" do
    assert {:ok, context} = context("<div>Hello |world</div>")

    assert context.kind == :text
    assert context.tag == nil
    assert context.attribute == nil
    assert context.prefix == ""
  end

  test "classifies html tag names" do
    assert {:ok, context} = context("<di|v></div>")

    assert context.kind == :tag_name
    assert context.tag == "di"
    assert context.prefix == "di"
    assert context.closing? == false
  end

  test "classifies function component tag names" do
    assert {:ok, context} = context("<.but|ton />")

    assert context.kind == :tag_name
    assert context.tag == ".but"
    assert context.prefix == ".but"
  end

  test "classifies slot tag names" do
    assert {:ok, context} = context("<:it|em>")

    assert context.kind == :tag_name
    assert context.tag == ":it"
    assert context.prefix == ":it"
  end

  test "classifies closing tag names" do
    assert {:ok, context} = context("</di|v>")

    assert context.kind == :tag_name
    assert context.tag == "di"
    assert context.prefix == "di"
    assert context.closing? == true
  end

  test "classifies empty attribute name position inside a tag" do
    assert {:ok, context} = context("<.button |>")

    assert context.kind == :attribute_name
    assert context.tag == ".button"
    assert context.attribute == nil
    assert context.prefix == ""
  end

  test "classifies partial attribute names inside a tag" do
    assert {:ok, context} = context("<.button phx-cl|ick=\"save\" />")

    assert context.kind == :attribute_name
    assert context.tag == ".button"
    assert context.attribute == nil
    assert context.prefix == "phx-cl"
  end

  test "classifies quoted attribute values" do
    assert {:ok, context} = context("<.button class=\"btn btn-|primary\" />")

    assert context.kind == :attribute_value
    assert context.tag == ".button"
    assert context.attribute == "class"
    assert context.prefix == "btn btn-"
  end

  test "classifies attribute expression values" do
    assert {:ok, context} = context("<.input field={@fo|rm[:name]} />")

    assert context.kind == :expression
    assert context.tag == ".input"
    assert context.attribute == "field"
  end

  test "classifies text expressions" do
    assert {:ok, context} = context("<p>{@na|me}</p>")

    assert context.kind == :expression
    assert context.tag == nil
    assert context.attribute == nil
  end

  test "uses UTF-16 LSP positions for cursor offsets" do
    assert {:ok, context} = context("<p>😀</p>\n<.but|ton />")

    assert context.kind == :tag_name
    assert context.prefix == ".but"
  end

  test "returns error for invalid positions" do
    assert CursorContext.at("<div></div>", %{line: 10, character: 0}) == :error
  end

  defp context(marked_source) do
    {source, position} = source_and_position(marked_source)

    CursorContext.at(source, position)
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
