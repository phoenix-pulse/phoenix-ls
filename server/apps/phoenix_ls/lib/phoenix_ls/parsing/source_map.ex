defmodule PhoenixLS.Parsing.SourceMap do
  @moduledoc """
  Maps offsets from embedded source back to the outer source document.
  """

  alias GenLSP.Structures.Range
  alias PhoenixLS.Support.Positions

  @enforce_keys [:source, :base_offset]
  defstruct [:source, :base_offset]

  @type t :: %__MODULE__{source: String.t(), base_offset: non_neg_integer()}

  @spec new(String.t(), non_neg_integer()) :: t()
  def new(source, base_offset \\ 0)
      when is_binary(source) and is_integer(base_offset) and base_offset >= 0 and
             base_offset <= byte_size(source) do
    %__MODULE__{source: source, base_offset: base_offset}
  end

  @spec to_source_offset(t(), non_neg_integer()) :: non_neg_integer() | :error
  def to_source_offset(%__MODULE__{} = map, embedded_offset)
      when is_integer(embedded_offset) and embedded_offset >= 0 do
    source_offset = map.base_offset + embedded_offset

    if source_offset <= byte_size(map.source) do
      source_offset
    else
      :error
    end
  end

  def to_source_offset(%__MODULE__{}, _embedded_offset), do: :error

  @spec to_lsp_position(t(), non_neg_integer()) :: {:ok, Positions.lsp_position()} | :error
  def to_lsp_position(%__MODULE__{} = map, embedded_offset) do
    case to_source_offset(map, embedded_offset) do
      offset when is_integer(offset) -> Positions.offset_to_lsp_position(map.source, offset)
      :error -> :error
    end
  end

  @spec to_lsp_range(t(), non_neg_integer(), non_neg_integer()) :: {:ok, Range.t()} | :error
  def to_lsp_range(%__MODULE__{} = map, start_offset, end_offset) do
    with {:ok, start_position} <- to_lsp_position(map, start_offset),
         {:ok, end_position} <- to_lsp_position(map, end_offset) do
      {:ok, %Range{start: start_position, end: end_position}}
    end
  end

  @spec range_from_meta(String.t(), keyword()) :: {:ok, Range.t()} | {:error, term()}
  def range_from_meta(source, meta) when is_binary(source) and is_list(meta) do
    if Keyword.get(meta, :generated, false) do
      {:error, :generated}
    else
      do_range_from_meta(source, meta)
    end
  end

  defp do_range_from_meta(source, meta) do
    end_meta = Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end) || meta

    with {:ok, start_offset} <- offset_from_meta(source, meta),
         {:ok, end_offset} <- offset_from_meta(source, end_meta) do
      to_lsp_range(new(source), start_offset, end_offset)
    end
  end

  defp offset_from_meta(source, meta) do
    with line when is_integer(line) and line > 0 <- Keyword.get(meta, :line),
         column when is_integer(column) and column > 0 <- Keyword.get(meta, :column) do
      Positions.lsp_position_to_offset(source, %{line: line - 1, character: column - 1})
    else
      _invalid -> {:error, :missing_location}
    end
  end
end
