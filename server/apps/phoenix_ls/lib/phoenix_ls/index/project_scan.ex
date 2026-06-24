defmodule PhoenixLS.Index.ProjectScan do
  @moduledoc """
  Enumerates source files that can be indexed without loading project code.
  """

  alias PhoenixLS.Support.URI, as: SupportURI

  @source_globs [
    "lib/**/*.ex",
    "lib/**/*.heex"
  ]

  @spec uris(String.t()) :: {:ok, [String.t()]} | {:error, :not_file_uri}
  def uris(root_uri) when is_binary(root_uri) do
    with {:ok, root_path} <- SupportURI.file_uri_to_path(root_uri) do
      uris =
        @source_globs
        |> Enum.flat_map(&Path.wildcard(Path.join(root_path, &1)))
        |> Enum.sort()
        |> Enum.map(&SupportURI.path_to_file_uri!/1)

      {:ok, uris}
    else
      {:error, _reason} -> {:error, :not_file_uri}
    end
  end
end
