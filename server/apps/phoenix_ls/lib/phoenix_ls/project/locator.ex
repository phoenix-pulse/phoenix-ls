defmodule PhoenixLS.Project.Locator do
  @moduledoc """
  Locates Mix project roots from LSP file URIs.
  """

  alias PhoenixLS.Support.URI, as: SupportURI

  @phoenix_dependencies MapSet.new([:phoenix, :phoenix_live_view])

  defmodule Result do
    @moduledoc """
    Located Mix project metadata.
    """

    @enforce_keys [:root_path, :root_uri, :mix_exs_path, :phoenix?]
    defstruct [
      :root_path,
      :root_uri,
      :mix_exs_path,
      :umbrella_root_path,
      :umbrella_root_uri,
      phoenix?: false
    ]

    @type t :: %__MODULE__{
            root_path: String.t(),
            root_uri: String.t(),
            mix_exs_path: String.t(),
            umbrella_root_path: String.t() | nil,
            umbrella_root_uri: String.t() | nil,
            phoenix?: boolean()
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
      umbrella_root_uri: umbrella_root_uri,
      phoenix?: phoenix_dependency?(mix_exs_path)
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

  defp phoenix_dependency?(mix_exs_path) do
    with {:ok, source} <- File.read(mix_exs_path),
         {:ok, quoted} <- Code.string_to_quoted(source) do
      {_quoted, found?} = Macro.prewalk(quoted, false, &detect_phoenix_dependency/2)

      found?
    else
      _error -> false
    end
  end

  defp detect_phoenix_dependency(node, true), do: {node, true}

  defp detect_phoenix_dependency({dependency, requirement} = node, false)
       when is_atom(dependency) and is_binary(requirement) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency({dependency, requirement, opts} = node, false)
       when is_atom(dependency) and is_binary(requirement) and is_list(opts) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency({:{}, _meta, [dependency | _rest]} = node, false)
       when is_atom(dependency) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency(node, false), do: {node, false}
end
