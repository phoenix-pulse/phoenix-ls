defmodule PhoenixLS.Project.Engine do
  @moduledoc """
  Per-project supervision island for runtime state.
  """

  use Supervisor

  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.Metadata
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Workspace.DocumentStore

  @enforce_keys [
    :root_uri,
    :pid,
    :document_store,
    :metadata,
    :index_store,
    :indexer,
    :source_only?
  ]
  defstruct [
    :root_uri,
    :pid,
    :document_store,
    :metadata,
    :index_store,
    :indexer,
    source_only?: true
  ]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          pid: pid(),
          document_store: GenServer.server(),
          metadata: GenServer.server(),
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
    index_store = Keyword.get(opts, :index_store, Names.index_store(root_uri))
    indexer = Keyword.get(opts, :indexer, Names.indexer(root_uri))
    status_target = Keyword.get(opts, :status_target)
    project_indexing_enabled = Keyword.get(opts, :project_indexing_enabled, true)

    children = [
      {DocumentStore, name: document_store},
      {Metadata, name: metadata, root_uri: root_uri},
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
end
