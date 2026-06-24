defmodule PhoenixLS.Introspection.Template do
  @moduledoc """
  Source-only extraction helpers for HEEx template documents and references.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Introspection.Template.RenderReferences

  defmodule Template do
    @moduledoc """
    Typed HEEx template fact payload.
    """

    @enforce_keys [:format]
    defstruct [:format]
  end

  @spec facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    [
      Fact.new!(
        kind: :template,
        id: uri,
        uri: uri,
        range: document_range(source),
        provenance: provenance(opts),
        data: %Template{
          format: :heex
        }
      )
    ]
  end

  @spec render_reference_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def render_reference_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    RenderReferences.facts(uri, source, opts)
  end

  defp document_range(source) do
    {:ok, end_position} = Positions.offset_to_lsp_position(source, byte_size(source))

    %Range{
      start: %Position{line: 0, character: 0},
      end: position(end_position)
    }
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
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
