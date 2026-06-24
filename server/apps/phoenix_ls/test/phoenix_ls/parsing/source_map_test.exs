defmodule PhoenixLS.Parsing.SourceMapTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.Range
  alias PhoenixLS.Parsing.SourceMap

  test "maps embedded HEEx offsets inside a sigil back to outer source positions" do
    source = "def render(assigns) do\r\n  ~H\"\"\"\r\n  <p>Hi 😀</p>\r\n  \"\"\"\r\nend\n"
    base_offset = byte_offset!(source, "<p>")
    map = SourceMap.new(source, base_offset)

    assert SourceMap.to_source_offset(map, byte_size("<p>Hi ")) ==
             base_offset + byte_size("<p>Hi ")

    assert SourceMap.to_lsp_position(map, byte_size("<p>Hi ")) ==
             {:ok, %{line: 2, character: 8}}
  end

  test "maps embedded ranges through CRLF and UTF-16 source positions" do
    source = "one\r\n~H\"\"\"\r\n<div>😀</div>\r\n\"\"\"\r\n"
    base_offset = byte_offset!(source, "<div>")
    map = SourceMap.new(source, base_offset)

    assert {:ok, %Range{} = range} =
             SourceMap.to_lsp_range(map, 0, byte_size("<div>😀</div>"))

    assert range.start == %{line: 2, character: 0}
    assert range.end == %{line: 2, character: 13}
  end

  test "converts Elixir parser metadata to an LSP range" do
    source = "first\n  second\n"

    assert {:ok, %Range{} = range} =
             SourceMap.range_from_meta(source,
               line: 2,
               column: 3,
               end_of_expression: [line: 2, column: 9]
             )

    assert range.start == %{line: 1, character: 2}
    assert range.end == %{line: 1, character: 8}
  end

  test "rejects generated metadata explicitly" do
    assert SourceMap.range_from_meta("value\n", generated: true, line: 1, column: 1) ==
             {:error, :generated}
  end

  defp byte_offset!(source, needle) do
    case :binary.match(source, needle) do
      {offset, _length} -> offset
      :nomatch -> raise ArgumentError, "missing #{inspect(needle)}"
    end
  end
end
