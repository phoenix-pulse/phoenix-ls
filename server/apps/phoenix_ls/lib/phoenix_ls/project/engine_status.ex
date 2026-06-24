defmodule PhoenixLS.Project.EngineStatus do
  @moduledoc """
  Manager-owned status for a project engine.
  """

  @enforce_keys [:root_uri, :state, :source_only?]
  defstruct [
    :root_uri,
    :state,
    :pid,
    :document_store,
    :index_store,
    :indexer,
    :reason,
    source_only?: true
  ]

  @type state :: :running | :missing | :degraded

  @type t :: %__MODULE__{
          root_uri: String.t(),
          state: state(),
          source_only?: boolean(),
          pid: pid() | nil,
          document_store: GenServer.server() | nil,
          index_store: GenServer.server() | nil,
          indexer: GenServer.server() | nil,
          reason: term()
        }

  @spec missing(String.t(), term()) :: t()
  def missing(root_uri, reason \\ :not_started) do
    %__MODULE__{
      root_uri: root_uri,
      state: :missing,
      source_only?: true,
      reason: reason
    }
  end

  @spec running(PhoenixLS.Project.Engine.t()) :: t()
  def running(engine) do
    %__MODULE__{
      root_uri: engine.root_uri,
      state: :running,
      source_only?: true,
      pid: engine.pid,
      document_store: engine.document_store,
      index_store: engine.index_store,
      indexer: engine.indexer
    }
  end

  @spec degraded(String.t(), term()) :: t()
  def degraded(root_uri, reason) do
    %__MODULE__{
      root_uri: root_uri,
      state: :degraded,
      source_only?: true,
      reason: reason
    }
  end
end
