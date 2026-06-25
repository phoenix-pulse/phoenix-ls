defmodule PhoenixLS.Introspection.Template do
  @moduledoc """
  Source-only extraction helpers for HEEx template documents and references.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Introspection.Template.RenderReferences

  defmodule Template do
    @moduledoc """
    Typed HEEx template fact payload.
    """

    @enforce_keys [:format, :name, :module, :kind]
    defstruct [:format, :name, :module, :kind]
  end

  @spec facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)

    [
      Fact.new!(
        kind: :template,
        id: uri,
        uri: uri,
        range: document_range(source),
        provenance: provenance(opts),
        data: %Template{
          format: :heex,
          name: metadata.name,
          module: metadata.module,
          kind: metadata.kind
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

  defp template_metadata(uri) do
    path = file_path(uri)
    name = template_name(path)
    {module_parts, kind} = module_parts(path, name)

    %{
      name: name,
      module: Enum.join(module_parts, "."),
      kind: kind
    }
  end

  defp file_path(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, _reason} -> uri
    end
  end

  defp template_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp module_parts(path, name) do
    case Enum.split_while(Path.split(path), &(&1 != "lib")) do
      {_before_lib, ["lib", web_root | rest]} ->
        {suffix, kind} =
          rest
          |> Enum.drop(-1)
          |> module_suffix(template_stem(name))

        {[module_segment(web_root) | suffix] |> Enum.reject(&(&1 == "")), kind}

      _path_without_lib ->
        {[], :template}
    end
  end

  defp module_suffix(["controllers" | dirs], _stem) do
    {Enum.map(dirs, &module_segment/1), :controller}
  end

  defp module_suffix(["components", "layouts" | dirs], _stem) do
    {Enum.map(["layouts" | dirs], &module_segment/1), :layout}
  end

  defp module_suffix(["components" | dirs], _stem) do
    {Enum.map(dirs, &module_segment/1), :component}
  end

  defp module_suffix(["live" | dirs], stem) do
    {Enum.map(dirs ++ [stem], &module_segment/1), :live_view}
  end

  defp module_suffix(dirs, _stem) do
    {
      dirs
      |> Enum.reject(&template_context_dir?/1)
      |> Enum.map(&module_segment/1),
      :template
    }
  end

  defp template_context_dir?(dir), do: dir in ["controllers", "live", "templates", "components"]

  defp template_stem(name) do
    name
    |> String.split(".", parts: 2)
    |> List.first()
  end

  defp module_segment(segment) do
    segment
    |> String.split("_")
    |> Enum.map(&module_word/1)
    |> Enum.join()
  end

  defp module_word(""), do: ""
  defp module_word("api"), do: "API"
  defp module_word("html"), do: "HTML"
  defp module_word("json"), do: "JSON"
  defp module_word(word), do: String.capitalize(word)
end
