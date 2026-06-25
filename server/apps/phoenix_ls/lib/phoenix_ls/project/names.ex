defmodule PhoenixLS.Project.Names do
  @moduledoc """
  Process names for project-scoped runtime state.
  """

  @registry PhoenixLS.Project.Registry

  @spec engine(String.t()) :: GenServer.server()
  def engine(root_uri), do: via({:engine, root_uri})

  @spec document_store(String.t()) :: GenServer.server()
  def document_store(root_uri), do: via({:document_store, root_uri})

  @spec metadata(String.t()) :: GenServer.server()
  def metadata(root_uri), do: via({:metadata, root_uri})

  @spec compile_env(String.t()) :: GenServer.server()
  def compile_env(root_uri), do: via({:compile_env, root_uri})

  @spec index_store(String.t()) :: GenServer.server()
  def index_store(root_uri), do: via({:index_store, root_uri})

  @spec indexer(String.t()) :: GenServer.server()
  def indexer(root_uri), do: via({:indexer, root_uri})

  defp via(key), do: {:via, Registry, {@registry, key}}
end
