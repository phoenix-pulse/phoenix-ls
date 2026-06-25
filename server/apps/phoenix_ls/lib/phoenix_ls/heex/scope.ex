defmodule PhoenixLS.HEEx.Scope do
  @moduledoc """
  Helpers for resolving HEEx tag scope at a source offset.
  """

  alias PhoenixLS.HEEx.Document.Tag
  alias PhoenixLS.Support.Positions

  @spec active_tags([Tag.t()], String.t(), non_neg_integer()) :: [Tag.t()]
  def active_tags(tags, source, offset) when is_list(tags) and is_binary(source) do
    Enum.filter(tags, &active_tag?(&1, source, offset))
  end

  defp active_tag?(%Tag{self_closing?: true}, _source, _offset), do: false

  defp active_tag?(%Tag{range: %{start: start}, closing_range: closing_range}, source, offset) do
    case Positions.lsp_position_to_offset(source, start) do
      {:ok, tag_offset} when tag_offset < offset -> before_closing?(closing_range, source, offset)
      {:ok, _tag_offset} -> false
      :error -> false
    end
  end

  defp before_closing?(nil, _source, _offset), do: true

  defp before_closing?(%{end: close_end}, source, offset) do
    case Positions.lsp_position_to_offset(source, close_end) do
      {:ok, close_offset} -> offset <= close_offset
      :error -> false
    end
  end
end
