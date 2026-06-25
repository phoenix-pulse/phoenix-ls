defmodule PhoenixLS.Index.ProjectScan do
  @moduledoc """
  Enumerates source files that can be indexed without loading project code.
  """

  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Introspection.Asset

  @source_globs [
    "lib/**/*.ex",
    "lib/**/*.heex",
    "priv/static/**/*",
    "apps/*/lib/**/*.ex",
    "apps/*/lib/**/*.heex",
    "apps/*/priv/static/**/*"
  ]

  @spec uris(String.t()) :: {:ok, [String.t()]} | {:error, :not_file_uri}
  def uris(root_uri) when is_binary(root_uri) do
    with {:ok, root_path} <- SupportURI.file_uri_to_path(root_uri) do
      uris =
        @source_globs
        |> Enum.flat_map(&Path.wildcard(Path.join(root_path, &1)))
        |> Enum.filter(&File.regular?/1)
        |> Enum.filter(&indexable_path?(&1, root_path))
        |> Enum.sort()
        |> Enum.map(&SupportURI.path_to_file_uri!/1)

      {:ok, uris}
    else
      {:error, _reason} -> {:error, :not_file_uri}
    end
  end

  defp indexable_path?(path, root_path) do
    Path.extname(path) in [".ex", ".heex"] or Asset.static_asset_path?(path, root_path)
  end
end
