defmodule PhoenixLS.Features.CodeAction.Ranges do
  @moduledoc """
  Source-range helpers for code-action text edits.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Support.Positions

  @spec insert_range(String.t(), Tag.t()) :: {:ok, Range.t()} | :error
  def insert_range(source, %Tag{} = tag) do
    with {:ok, end_offset} <- Positions.lsp_position_to_offset(source, tag.range.end),
         true <- end_offset > 0,
         {:ok, insert_offset} <- insert_offset(source, end_offset - 1, tag.self_closing?),
         {:ok, position} <- Positions.offset_to_lsp_position(source, insert_offset) do
      position = %Position{line: position.line, character: position.character}

      {:ok, %Range{start: position, end: position}}
    else
      _error -> :error
    end
  end

  @spec attr_removal_range(String.t(), Attribute.t()) :: {:ok, Range.t()} | :error
  def attr_removal_range(source, %Attribute{range: range}) do
    with {:ok, start_offset} <- Positions.lsp_position_to_offset(source, range.start),
         {:ok, start} <-
           Positions.offset_to_lsp_position(
             source,
             rewind_inline_whitespace(source, start_offset)
           ) do
      {:ok, %Range{start: position(start), end: range.end}}
    else
      _error -> :error
    end
  end

  @spec tag_removal_range(Tag.t()) :: Range.t()
  def tag_removal_range(%Tag{range: %{start: start}, closing_range: %{end: end_position}}) do
    %Range{start: start, end: end_position}
  end

  def tag_removal_range(%Tag{range: %Range{} = range}), do: range

  @spec zero_width(Position.t()) :: Range.t()
  def zero_width(%Position{} = position), do: %Range{start: position, end: position}

  defp insert_offset(_source, gt_offset, false), do: {:ok, gt_offset}

  defp insert_offset(source, gt_offset, true) do
    with {:ok, slash_offset} <- previous_non_whitespace(source, gt_offset - 1) do
      {:ok, rewind_whitespace(source, slash_offset - 1)}
    end
  end

  defp previous_non_whitespace(_source, offset) when offset < 0, do: :error

  defp previous_non_whitespace(source, offset) do
    if whitespace_at?(source, offset) do
      previous_non_whitespace(source, offset - 1)
    else
      {:ok, offset}
    end
  end

  defp rewind_whitespace(_source, offset) when offset < 0, do: 0

  defp rewind_whitespace(source, offset) do
    if whitespace_at?(source, offset) do
      rewind_whitespace(source, offset - 1)
    else
      offset + 1
    end
  end

  defp whitespace_at?(source, offset) do
    :binary.at(source, offset) in [?\s, ?\t, ?\n, ?\r]
  end

  defp rewind_inline_whitespace(_source, 0), do: 0

  defp rewind_inline_whitespace(source, offset) do
    previous_offset = offset - 1

    if inline_whitespace_at?(source, previous_offset) do
      rewind_inline_whitespace(source, previous_offset)
    else
      offset
    end
  end

  defp inline_whitespace_at?(source, offset) when offset >= 0 do
    :binary.at(source, offset) in [?\s, ?\t]
  end

  defp inline_whitespace_at?(_source, _offset), do: false

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end
end
