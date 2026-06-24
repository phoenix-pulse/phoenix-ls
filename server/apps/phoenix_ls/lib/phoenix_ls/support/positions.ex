defmodule PhoenixLS.Support.Positions do
  @moduledoc """
  Converts between LSP positions and Elixir byte offsets.

  LSP characters are UTF-16 code units. Returned offsets are byte offsets into
  the original UTF-8 text.
  """

  @type lsp_position :: %{line: non_neg_integer(), character: non_neg_integer()}

  @spec lsp_position_to_offset(String.t(), lsp_position()) :: {:ok, non_neg_integer()} | :error
  def lsp_position_to_offset(text, %{line: line, character: character})
      when is_binary(text) and is_integer(line) and is_integer(character) and line >= 0 and
             character >= 0 do
    find_offset(text, line, character, 0, 0, 0)
  end

  def lsp_position_to_offset(_text, _position), do: :error

  @spec offset_to_lsp_position(String.t(), non_neg_integer()) :: {:ok, lsp_position()} | :error
  def offset_to_lsp_position(text, byte_offset)
      when is_binary(text) and is_integer(byte_offset) and byte_offset >= 0 and
             byte_offset <= byte_size(text) do
    find_position(text, byte_offset, 0, 0, 0)
  end

  def offset_to_lsp_position(_text, _byte_offset), do: :error

  defp find_offset(<<>>, target_line, target_character, line, character, byte_offset) do
    if line == target_line and character == target_character do
      {:ok, byte_offset}
    else
      :error
    end
  end

  defp find_offset(text, target_line, target_character, line, character, byte_offset) do
    cond do
      line == target_line and character == target_character ->
        {:ok, byte_offset}

      line > target_line ->
        :error

      true ->
        advance_offset(text, target_line, target_character, line, character, byte_offset)
    end
  end

  defp advance_offset(
         <<?\r, ?\n, rest::binary>>,
         target_line,
         target_character,
         line,
         _character,
         byte_offset
       ) do
    if line == target_line do
      :error
    else
      find_offset(rest, target_line, target_character, line + 1, 0, byte_offset + 2)
    end
  end

  defp advance_offset(
         <<?\n, rest::binary>>,
         target_line,
         target_character,
         line,
         _character,
         byte_offset
       ) do
    if line == target_line do
      :error
    else
      find_offset(rest, target_line, target_character, line + 1, 0, byte_offset + 1)
    end
  end

  defp advance_offset(text, target_line, target_character, line, character, byte_offset) do
    case text do
      <<codepoint::utf8, rest::binary>> ->
        codepoint_bytes = byte_size(text) - byte_size(rest)
        next_character = character + utf16_code_units(codepoint)

        if line == target_line and target_character < next_character do
          :error
        else
          find_offset(
            rest,
            target_line,
            target_character,
            line,
            next_character,
            byte_offset + codepoint_bytes
          )
        end

      _invalid_utf8 ->
        :error
    end
  end

  defp find_position(_text, target_offset, line, character, byte_offset)
       when target_offset == byte_offset do
    {:ok, %{line: line, character: character}}
  end

  defp find_position(<<>>, _target_offset, _line, _character, _byte_offset), do: :error

  defp find_position(text, target_offset, line, character, byte_offset) do
    case text do
      <<?\r, ?\n, rest::binary>> ->
        next_offset = byte_offset + 2

        if target_offset < next_offset do
          :error
        else
          find_position(rest, target_offset, line + 1, 0, next_offset)
        end

      <<?\n, rest::binary>> ->
        find_position(rest, target_offset, line + 1, 0, byte_offset + 1)

      <<codepoint::utf8, rest::binary>> ->
        codepoint_bytes = byte_size(text) - byte_size(rest)
        next_offset = byte_offset + codepoint_bytes

        if target_offset < next_offset do
          :error
        else
          find_position(
            rest,
            target_offset,
            line,
            character + utf16_code_units(codepoint),
            next_offset
          )
        end

      _invalid_utf8 ->
        :error
    end
  end

  defp utf16_code_units(codepoint) when codepoint > 0xFFFF, do: 2
  defp utf16_code_units(_codepoint), do: 1
end
