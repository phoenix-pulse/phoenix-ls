defmodule PhoenixLS.Introspection.Template do
  @moduledoc """
  Source-only extraction helpers for HEEx template documents.
  """

  alias GenLSP.Structures.Range
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    [
      Fact.new!(
        kind: :template,
        id: uri,
        uri: uri,
        range: document_range(source),
        provenance: provenance(opts),
        data: %{
          format: :heex
        }
      )
    ]
  end

  defp document_range(source) do
    {:ok, end_position} = Positions.offset_to_lsp_position(source, byte_size(source))

    %Range{
      start: %{line: 0, character: 0},
      end: end_position
    }
  end

  defp provenance(opts) do
    provenance = %{
      source: :heex_template
    }

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end
end
