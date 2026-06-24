defmodule PhoenixLS.Project.Engine do
  @moduledoc """
  Per-project supervision island for runtime state.
  """

  use Supervisor

  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.Index.Store, as: IndexStore
  alias PhoenixLS.Project.Names
  alias PhoenixLS.Workspace.DocumentStore

  @enforce_keys [:root_uri, :pid, :document_store, :index_store, :indexer]
  defstruct [:root_uri, :pid, :document_store, :index_store, :indexer]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          pid: pid(),
          document_store: GenServer.server(),
          index_store: GenServer.server(),
          indexer: GenServer.server()
        }

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    name = Keyword.get(opts, :name, Names.engine(root_uri))

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec handle(String.t(), pid()) :: t()
  def handle(root_uri, pid) do
    %__MODULE__{
      root_uri: root_uri,
      pid: pid,
      document_store: Names.document_store(root_uri),
      index_store: Names.index_store(root_uri),
      indexer: Names.indexer(root_uri)
    }
  end

  @impl true
  def init(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    document_store = Keyword.get(opts, :document_store, Names.document_store(root_uri))
    index_store = Keyword.get(opts, :index_store, Names.index_store(root_uri))
    indexer = Keyword.get(opts, :indexer, Names.indexer(root_uri))
    status_target = Keyword.get(opts, :status_target)

    children = [
      {DocumentStore, name: document_store},
      {IndexStore, name: index_store},
      {Indexer,
       name: indexer, index_store: index_store, root_uri: root_uri, status_target: status_target}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
