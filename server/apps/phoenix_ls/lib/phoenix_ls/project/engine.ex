defmodule PhoenixLS.Project.Engine do
  @moduledoc """
  Per-project supervision island for runtime state.
  """

  use Supervisor

  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.CompileEnv
  alias PhoenixLS.Project.CompileRunner
  alias PhoenixLS.Project.Metadata
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Workspace.DocumentStore

  @enforce_keys [
    :root_uri,
    :pid,
    :document_store,
    :metadata,
    :compile_env,
    :compile_runner,
    :index_store,
    :indexer,
    :source_only?
  ]
  defstruct [
    :root_uri,
    :pid,
    :document_store,
    :metadata,
    :compile_env,
    :compile_runner,
    :index_store,
    :indexer,
    source_only?: true
  ]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          pid: pid(),
          document_store: GenServer.server(),
          metadata: GenServer.server(),
          compile_env: GenServer.server(),
          compile_runner: GenServer.server(),
          index_store: GenServer.server(),
          indexer: GenServer.server(),
          source_only?: boolean()
        }

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    name = Keyword.get(opts, :name, Names.engine(root_uri))

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec handle(String.t(), pid(), keyword()) :: t()
  def handle(root_uri, pid, opts \\ []) do
    %__MODULE__{
      root_uri: root_uri,
      pid: pid,
      document_store: Names.document_store(root_uri),
      metadata: Names.metadata(root_uri),
      compile_env: Names.compile_env(root_uri),
      compile_runner: Names.compile_runner(root_uri),
      index_store: Names.index_store(root_uri),
      indexer: Names.indexer(root_uri),
      source_only?: Keyword.get(opts, :source_only?, true)
    }
  end

  @impl true
  def init(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    document_store = Keyword.get(opts, :document_store, Names.document_store(root_uri))
    metadata = Keyword.get(opts, :metadata, Names.metadata(root_uri))
    compile_env = Keyword.get(opts, :compile_env, Names.compile_env(root_uri))
    compile_runner = Keyword.get(opts, :compile_runner, Names.compile_runner(root_uri))
    index_store = Keyword.get(opts, :index_store, Names.index_store(root_uri))
    indexer = Keyword.get(opts, :indexer, Names.indexer(root_uri))
    status_target = Keyword.get(opts, :status_target)
    project_indexing_enabled = Keyword.get(opts, :project_indexing_enabled, true)
    source_only? = Keyword.get(opts, :source_only?, true)
    compile_timeout_ms = Keyword.get(opts, :compile_timeout_ms, 5_000)
    compile_cache_root = Keyword.get(opts, :compile_cache_root)

    children = [
      {DocumentStore, name: document_store},
      {Metadata, name: metadata, root_uri: root_uri},
      {CompileEnv,
       compile_env_opts(
         compile_env,
         root_uri,
         source_only?,
         compile_timeout_ms,
         compile_cache_root
       )},
      {CompileRunner, name: compile_runner, compile_env: compile_env},
      {IndexStore, name: index_store},
      {Indexer,
       name: indexer,
       index_store: index_store,
       root_uri: root_uri,
       status_target: status_target,
       project_indexing_enabled: project_indexing_enabled}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp compile_env_opts(name, root_uri, source_only?, timeout_ms, cache_root) do
    [
      name: name,
      root_uri: root_uri,
      source_only?: source_only?,
      timeout_ms: timeout_ms
    ]
    |> maybe_put_compile_cache_root(cache_root)
  end

  defp maybe_put_compile_cache_root(opts, cache_root) when is_binary(cache_root) do
    Keyword.put(opts, :cache_root, cache_root)
  end

  defp maybe_put_compile_cache_root(opts, _cache_root), do: opts
end
