defmodule PhoenixLS.Index.Store do
  @moduledoc """
  ETS-backed store for project-scoped indexed facts.
  """

  use GenServer

  alias PhoenixLS.Index.Fact

  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec put(server(), Fact.t()) :: :ok
  def put(server \\ __MODULE__, %Fact{} = fact) do
    GenServer.call(server, {:put, fact})
  end

  @spec all(server()) :: [Fact.t()]
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  end

  @spec by_uri(server(), String.t()) :: [Fact.t()]
  def by_uri(server \\ __MODULE__, uri) when is_binary(uri) do
    GenServer.call(server, {:by_uri, uri})
  end

  @spec by_kind(server(), atom()) :: [Fact.t()]
  def by_kind(server \\ __MODULE__, kind) when is_atom(kind) do
    GenServer.call(server, {:by_kind, kind})
  end

  @spec delete_uri(server(), String.t()) :: :ok
  def delete_uri(server \\ __MODULE__, uri) when is_binary(uri) do
    GenServer.call(server, {:delete_uri, uri})
  end

  @spec clear(server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:set, :private])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:put, fact}, _from, state) do
    true = :ets.insert(state.table, {Fact.key(fact), fact})

    {:reply, :ok, state}
  end

  def handle_call(:all, _from, state) do
    {:reply, facts(state.table), state}
  end

  def handle_call({:by_uri, uri}, _from, state) do
    filtered =
      state.table
      |> facts()
      |> Enum.filter(&(&1.uri == uri))

    {:reply, filtered, state}
  end

  def handle_call({:by_kind, kind}, _from, state) do
    filtered =
      state.table
      |> facts()
      |> Enum.filter(&(&1.kind == kind))

    {:reply, filtered, state}
  end

  def handle_call({:delete_uri, uri}, _from, state) do
    state.table
    |> facts()
    |> Enum.filter(&(&1.uri == uri))
    |> Enum.each(&:ets.delete(state.table, Fact.key(&1)))

    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    true = :ets.delete_all_objects(state.table)

    {:reply, :ok, state}
  end

  defp facts(table) do
    table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _fact} -> key end)
    |> Enum.map(fn {_key, fact} -> fact end)
  end
end
