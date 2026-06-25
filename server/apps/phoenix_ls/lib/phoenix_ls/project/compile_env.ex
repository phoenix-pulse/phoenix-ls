defmodule PhoenixLS.Project.CompileEnv do
  @moduledoc """
  Engine-owned Mix environment paths for project-aware work.
  """

  use GenServer

  alias PhoenixLS.Support.URI, as: SupportURI

  @default_timeout_ms 5_000

  @enforce_keys [:root_uri]
  defstruct [
    :root_uri,
    :root_path,
    :cache_root,
    :build_path,
    :deps_path,
    :mix_home,
    :archives_path,
    source_only?: true,
    timeout_ms: @default_timeout_ms
  ]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          root_path: String.t() | nil,
          cache_root: String.t() | nil,
          build_path: String.t() | nil,
          deps_path: String.t() | nil,
          mix_home: String.t() | nil,
          archives_path: String.t() | nil,
          source_only?: boolean(),
          timeout_ms: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec fetch(GenServer.server()) :: t()
  def fetch(server), do: GenServer.call(server, :fetch)

  @spec mix_env(t()) :: %{String.t() => String.t()}
  def mix_env(%__MODULE__{} = env) do
    %{
      "MIX_BUILD_PATH" => env.build_path,
      "MIX_DEPS_PATH" => env.deps_path,
      "MIX_HOME" => env.mix_home,
      "MIX_ARCHIVES" => env.archives_path
    }
  end

  @impl true
  def init(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)

    {:ok, build(root_uri, opts)}
  end

  @impl true
  def handle_call(:fetch, _from, env) do
    {:reply, env, env}
  end

  defp build(root_uri, opts) do
    cache_root = Keyword.get(opts, :cache_root, default_cache_root())
    source_only? = Keyword.get(opts, :source_only?, true)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    case SupportURI.file_uri_to_path(root_uri) do
      {:ok, root_path} ->
        project_cache_root = Path.join(cache_root, project_cache_id(root_uri))

        %__MODULE__{
          root_uri: root_uri,
          root_path: root_path,
          cache_root: cache_root,
          build_path: Path.join(project_cache_root, "_build"),
          deps_path: Path.join(project_cache_root, "deps"),
          mix_home: Path.join(project_cache_root, "mix_home"),
          archives_path: Path.join(project_cache_root, "archives"),
          source_only?: source_only?,
          timeout_ms: timeout_ms
        }
        |> ensure_dirs!()

      {:error, _reason} ->
        %__MODULE__{
          root_uri: root_uri,
          cache_root: cache_root,
          source_only?: source_only?,
          timeout_ms: timeout_ms
        }
    end
  end

  defp ensure_dirs!(%__MODULE__{} = env) do
    env
    |> owned_dirs()
    |> Enum.each(&File.mkdir_p!/1)

    env
  end

  defp owned_dirs(%__MODULE__{} = env) do
    [
      env.build_path,
      env.deps_path,
      env.mix_home,
      env.archives_path
    ]
  end

  defp default_cache_root do
    Path.join(System.tmp_dir!(), "phoenix_ls_project_env")
  end

  defp project_cache_id(root_uri) do
    digest =
      :sha256
      |> :crypto.hash(root_uri)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)

    "project_#{digest}"
  end
end
