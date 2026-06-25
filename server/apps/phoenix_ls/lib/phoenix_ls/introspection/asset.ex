defmodule PhoenixLS.Introspection.Asset do
  @moduledoc """
  Source-only extraction helpers for Phoenix static asset facts.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Asset.Hooks, as: AssetHooks

  defmodule Asset do
    @moduledoc """
    Typed static asset fact payload.
    """

    @enforce_keys [:public_path, :file_path, :type, :size]
    defstruct [:public_path, :file_path, :type, :size]
  end

  @image_extensions [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico", ".bmp"]
  @style_extensions [".css", ".scss", ".sass", ".less"]
  @script_extensions [".js", ".mjs", ".jsx", ".ts", ".tsx"]
  @font_extensions [".woff", ".woff2", ".ttf", ".otf", ".eot"]
  @asset_extensions @image_extensions ++
                      @style_extensions ++ @script_extensions ++ @font_extensions

  @spec supported_path?(String.t()) :: boolean()
  def supported_path?(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @asset_extensions))
  end

  @spec static_asset_path?(String.t(), String.t()) :: boolean()
  def static_asset_path?(path, root_path) when is_binary(path) and is_binary(root_path) do
    expanded_path = Path.expand(path)

    supported_path?(expanded_path) and
      match?({:ok, _root}, static_root_for_path(expanded_path, root_path))
  end

  @spec facts(String.t(), String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, path, root_path, opts \\ [])
      when is_binary(uri) and is_binary(path) and is_binary(root_path) do
    with true <- static_asset_path?(path, root_path),
         {:ok, public_path} <- public_path(path, root_path),
         {:ok, stat} <- File.stat(path) do
      type = asset_type(path)
      asset_provenance = provenance(opts)

      asset_fact =
        Fact.new!(
          kind: :asset,
          id: public_path,
          uri: uri,
          range: zero_range(),
          provenance: asset_provenance,
          data: %Asset{
            public_path: public_path,
            file_path: path,
            type: type,
            size: stat.size
          }
        )

      [asset_fact | script_hook_facts(type, uri, path, asset_provenance)]
    else
      _ignored -> []
    end
  end

  defp public_path(path, root_path) do
    expanded_path = Path.expand(path)

    with {:ok, static_root} <- static_root_for_path(expanded_path, root_path) do
      public_path =
        expanded_path
        |> Path.relative_to(static_root)
        |> Path.split()
        |> Enum.join("/")

      {:ok, "/" <> public_path}
    else
      _outside_static_roots -> :error
    end
  end

  defp static_root_for_path(path, root_path) do
    root_path
    |> static_roots()
    |> Enum.find(&under_path?(path, &1))
    |> case do
      nil -> :error
      static_root -> {:ok, static_root}
    end
  end

  defp static_roots(root_path) do
    expanded_root = Path.expand(root_path)

    [
      Path.join(expanded_root, "priv/static")
      | Path.wildcard(Path.join(expanded_root, "apps/*/priv/static"))
    ]
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp under_path?(path, root) do
    path_segments = Path.split(path)
    root_segments = Path.split(root)

    Enum.take(path_segments, length(root_segments)) == root_segments
  end

  defp asset_type(path) do
    extension =
      path
      |> Path.extname()
      |> String.downcase()

    cond do
      extension in @image_extensions -> :image
      extension in @style_extensions -> :style
      extension in @script_extensions -> :script
      extension in @font_extensions -> :font
    end
  end

  defp script_hook_facts(:script, uri, path, provenance) do
    case File.read(path) do
      {:ok, source} -> AssetHooks.facts(uri, source, provenance)
      {:error, _reason} -> []
    end
  end

  defp script_hook_facts(_type, _uri, _path, _provenance), do: []

  defp zero_range do
    %Range{
      start: %Position{line: 0, character: 0},
      end: %Position{line: 0, character: 0}
    }
  end

  defp provenance(opts) do
    provenance = %{source: :static_asset}

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end
end
