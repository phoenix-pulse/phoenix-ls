defmodule PhoenixLS.Introspection.Template.RenderReferences do
  @moduledoc """
  Extracts source-ranged controller render references to HEEx templates.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Parsing.SourceMap
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Introspection.Template.RenderCall

  defmodule Reference do
    @moduledoc """
    Typed controller render call reference payload.
    """

    @enforce_keys [:template, :format, :candidate_uris]
    defstruct [:template, :format, :candidate_uris]
  end

  @spec facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    case RenderCall.tokenize(source) do
      {:ok, tokens} ->
        tokens
        |> Enum.with_index()
        |> Enum.flat_map(&fact_for_token(&1, tokens, uri, source, opts))

      :error ->
        []
    end
  end

  defp fact_for_token({token, index}, tokens, uri, source, opts) do
    with {:ok, template, format} <- template_literal(token),
         true <- RenderCall.template_argument?(tokens, index),
         {:ok, range} <- token_range(source, token) do
      [
        Fact.new!(
          kind: :template_reference,
          id: render_reference_id(uri, range),
          uri: uri,
          range: range,
          provenance: provenance(opts),
          data: %Reference{
            template: template,
            format: format,
            candidate_uris: RenderCall.candidate_uris(uri, template, format)
          }
        )
      ]
    else
      _not_render_template -> []
    end
  end

  defp template_literal({:atom, _meta, value}) when is_atom(value) do
    {:ok, Atom.to_string(value), "html"}
  end

  defp template_literal({:bin_string, _meta, [value]}) when is_binary(value) do
    {:ok, template_name(value), template_format(value)}
  end

  defp template_literal(_token), do: :error

  defp token_range(source, token) do
    with {:ok, start_offset} <- token_start_offset(source, token),
         {:ok, end_offset} <- token_end_offset(source, token, start_offset) do
      SourceMap.to_lsp_range(SourceMap.new(source), start_offset, end_offset)
    end
  end

  defp token_start_offset(source, token) do
    with {line, column, _metadata} <- token_meta(token) do
      Positions.lsp_position_to_offset(source, %{line: line - 1, character: column - 1})
    else
      _invalid -> :error
    end
  end

  defp token_meta({_type, meta}), do: meta
  defp token_meta({_type, meta, _value}), do: meta

  defp token_end_offset(_source, {:atom, {_line, _column, chars}, _value}, start_offset)
       when is_list(chars) do
    {:ok, start_offset + byte_size(IO.iodata_to_binary(chars))}
  end

  defp token_end_offset(source, {:bin_string, _meta, _value}, start_offset) do
    quoted_literal_end_offset(source, start_offset)
  end

  defp token_end_offset(_source, _token, _start_offset), do: :error

  defp quoted_literal_end_offset(source, start_offset) do
    with quote when quote in [?\", ?'] <- :binary.at(source, start_offset) do
      scan_quoted_literal(source, start_offset + 1, quote, false)
    else
      _not_quoted -> :error
    end
  end

  defp scan_quoted_literal(source, offset, _quote, _escaped?) when offset >= byte_size(source),
    do: :error

  defp scan_quoted_literal(source, offset, quote, true) do
    scan_quoted_literal(source, offset + 1, quote, false)
  end

  defp scan_quoted_literal(source, offset, quote, false) do
    case :binary.at(source, offset) do
      ?\\ -> scan_quoted_literal(source, offset + 1, quote, true)
      ^quote -> {:ok, offset + 1}
      _other -> scan_quoted_literal(source, offset + 1, quote, false)
    end
  end

  defp render_reference_id(uri, range) do
    "render:#{uri}:#{range.start.line}:#{range.start.character}"
  end

  defp template_name(value) do
    value
    |> Path.basename()
    |> Path.rootname()
  end

  defp template_format(value) do
    case value |> Path.basename() |> Path.extname() do
      "." <> format -> format
      "" -> "html"
    end
  end

  defp provenance(opts) do
    provenance = %{
      source: :elixir_tokenizer,
      parser: :elixir_tokenizer
    }

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end
end
