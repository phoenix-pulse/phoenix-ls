defmodule PhoenixLS.Support.PositionsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Support.Positions

  test "converts zero-based LSP line and UTF-16 character to byte offset" do
    text = "abc\nhello"

    assert Positions.lsp_position_to_offset(text, %{line: 1, character: 2}) == {:ok, 6}
  end

  test "counts astral codepoints as two UTF-16 code units" do
    text = "a😀b"

    assert Positions.lsp_position_to_offset(text, %{line: 0, character: 3}) ==
             {:ok, byte_size("a😀")}

    assert Positions.offset_to_lsp_position(text, byte_size("a😀")) ==
             {:ok, %{line: 0, character: 3}}
  end

  test "handles CRLF line endings" do
    text = "one\r\ntwo"

    assert Positions.lsp_position_to_offset(text, %{line: 1, character: 0}) ==
             {:ok, byte_size("one\r\n")}

    assert Positions.offset_to_lsp_position(text, byte_size("one\r\n")) ==
             {:ok, %{line: 1, character: 0}}
  end

  test "converts the only valid empty string position" do
    assert Positions.lsp_position_to_offset("", %{line: 0, character: 0}) == {:ok, 0}
    assert Positions.offset_to_lsp_position("", 0) == {:ok, %{line: 0, character: 0}}
  end

  test "returns error for invalid lines" do
    assert Positions.lsp_position_to_offset("abc", %{line: 1, character: 0}) == :error
    assert Positions.lsp_position_to_offset("abc", %{line: -1, character: 0}) == :error
  end

  test "returns error for characters past the end of a line" do
    assert Positions.lsp_position_to_offset("abc", %{line: 0, character: 4}) == :error
    assert Positions.lsp_position_to_offset("abc", %{line: 0, character: -1}) == :error
  end

  test "returns error for UTF-16 characters inside an astral codepoint" do
    assert Positions.lsp_position_to_offset("a😀b", %{line: 0, character: 2}) == :error
  end

  test "returns error for byte offsets beyond the end" do
    assert Positions.offset_to_lsp_position("abc", 4) == :error
    assert Positions.offset_to_lsp_position("abc", -1) == :error
  end

  test "returns error for byte offsets inside a multibyte character" do
    text = "a😀b"

    assert Positions.offset_to_lsp_position(text, byte_size("a") + 1) == :error
  end

  test "supports the empty final line after a line ending" do
    text = "abc\n"

    assert Positions.lsp_position_to_offset(text, %{line: 1, character: 0}) ==
             {:ok, byte_size(text)}

    assert Positions.offset_to_lsp_position(text, byte_size(text)) ==
             {:ok, %{line: 1, character: 0}}
  end
end
