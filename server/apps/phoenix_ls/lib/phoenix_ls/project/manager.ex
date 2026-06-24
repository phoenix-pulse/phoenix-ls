defmodule PhoenixLS.Project.Manager do
  @moduledoc """
  Manager-side API for project engine ownership.
  """

  use GenServer

  alias PhoenixLS.Project.Engine

  @default_name __MODULE__
  @default_engine_supervisor PhoenixLS.Project.EngineSupervisor
  @registry PhoenixLS.Project.Registry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec ensure_engine(GenServer.server(), String.t()) :: {:ok, Engine.t()} | {:error, term()}
  def ensure_engine(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:ensure_engine, root_uri})
  end

  @spec fetch_engine(GenServer.server(), String.t()) :: {:ok, Engine.t()} | :error
  def fetch_engine(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:fetch_engine, root_uri})
  end

  @spec document_store(GenServer.server(), String.t()) :: {:ok, GenServer.server()} | :error
  def document_store(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:document_store, root_uri})
  end

  @impl true
  def init(opts) do
    state = %{
      engine_supervisor: Keyword.get(opts, :engine_supervisor, @default_engine_supervisor)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:ensure_engine, root_uri}, _from, state) do
    {:reply, ensure_engine_started(state.engine_supervisor, root_uri), state}
  end

  def handle_call({:fetch_engine, root_uri}, _from, state) do
    {:reply, fetch_engine_handle(root_uri), state}
  end

  def handle_call({:document_store, root_uri}, _from, state) do
    reply =
      case fetch_engine_handle(root_uri) do
        {:ok, engine} -> {:ok, engine.document_store}
        :error -> :error
      end

    {:reply, reply, state}
  end

  defp ensure_engine_started(engine_supervisor, root_uri) do
    case fetch_engine_handle(root_uri) do
      {:ok, engine} ->
        {:ok, engine}

      :error ->
        start_engine(engine_supervisor, root_uri)
    end
  end

  defp start_engine(engine_supervisor, root_uri) do
    case DynamicSupervisor.start_child(engine_supervisor, {Engine, root_uri: root_uri}) do
      {:ok, pid} -> {:ok, Engine.handle(root_uri, pid)}
      {:error, {:already_started, pid}} -> {:ok, Engine.handle(root_uri, pid)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_engine_handle(root_uri) do
    case Registry.lookup(@registry, {:engine, root_uri}) do
      [{pid, _value}] -> {:ok, Engine.handle(root_uri, pid)}
      [] -> :error
    end
  end
end
