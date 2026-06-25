defmodule PhoenixLS.Project.Locator do
  @moduledoc """
  Locates Mix project roots from LSP file URIs.
  """

  alias PhoenixLS.Support.URI, as: SupportURI

  defmodule Result do
    @moduledoc """
    Located Mix project paths.
    """

    @enforce_keys [:root_path, :root_uri, :mix_exs_path]
    defstruct [
      :root_path,
      :root_uri,
      :mix_exs_path,
      :umbrella_root_path,
      :umbrella_root_uri
    ]

    @type t :: %__MODULE__{
            root_path: String.t(),
            root_uri: String.t(),
            mix_exs_path: String.t(),
            umbrella_root_path: String.t() | nil,
            umbrella_root_uri: String.t() | nil
          }
  end

  @spec locate(String.t()) :: {:ok, Result.t()} | :error | {:error, term()}
  def locate(uri) when is_binary(uri) do
    with {:ok, path} <- SupportURI.file_uri_to_path(uri),
         start_dir <- start_dir(path),
         {:ok, root_path} <- find_mix_root(start_dir) do
      {:ok, result(root_path)}
    else
      :error -> :error
      {:error, _reason} = error -> error
    end
  end

  defp start_dir(path) do
    cond do
      File.dir?(path) -> path
      File.regular?(path) -> Path.dirname(path)
      Path.extname(path) != "" -> Path.dirname(path)
      true -> path
    end
  end

  defp find_mix_root(start_dir) do
    start_dir
    |> ancestors()
    |> Enum.find(&File.regular?(Path.join(&1, "mix.exs")))
    |> case do
      nil -> :error
      root_path -> {:ok, root_path}
    end
  end

  defp ancestors(path) do
    path = Path.expand(path)
    parent = Path.dirname(path)

    if parent == path do
      [path]
    else
      [path | ancestors(parent)]
    end
  end

  defp result(root_path) do
    mix_exs_path = Path.join(root_path, "mix.exs")
    {umbrella_root_path, umbrella_root_uri} = umbrella_root(root_path)

    %Result{
      root_path: root_path,
      root_uri: SupportURI.path_to_file_uri!(root_path),
      mix_exs_path: mix_exs_path,
      umbrella_root_path: umbrella_root_path,
      umbrella_root_uri: umbrella_root_uri
    }
  end

  defp umbrella_root(root_path) do
    apps_dir = Path.dirname(root_path)
    umbrella_root_path = Path.dirname(apps_dir)
    umbrella_mix_exs_path = Path.join(umbrella_root_path, "mix.exs")

    if Path.basename(apps_dir) == "apps" and File.regular?(umbrella_mix_exs_path) do
      {umbrella_root_path, SupportURI.path_to_file_uri!(umbrella_root_path)}
    else
      {nil, nil}
    end
  end
end
