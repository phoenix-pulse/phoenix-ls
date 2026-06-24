defmodule PhoenixLS.Workspace.DocumentStore do
  @moduledoc """
  GenServer-owned store for currently open editor documents.
  """

  use GenServer

  alias PhoenixLS.Workspace.Document

  @type uri :: String.t()
  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @spec open(server(), uri(), String.t(), integer(), String.t()) :: :ok
  def open(server \\ __MODULE__, uri, language_id, version, text) do
    GenServer.call(server, {:open, uri, language_id, version, text})
  end

  @spec replace(server(), uri(), integer(), String.t()) :: :ok | {:error, :not_found}
  def replace(server \\ __MODULE__, uri, version, text) do
    GenServer.call(server, {:replace, uri, version, text})
  end

  @spec fetch(server(), uri()) :: {:ok, Document.t()} | :error
  def fetch(server \\ __MODULE__, uri) do
    GenServer.call(server, {:fetch, uri})
  end

  @spec open_documents(server()) :: [Document.t()]
  def open_documents(server \\ __MODULE__) do
    GenServer.call(server, :open_documents)
  end

  @spec close(server(), uri()) :: :ok
  def close(server \\ __MODULE__, uri) do
    GenServer.call(server, {:close, uri})
  end

  @impl true
  def init(documents) do
    {:ok, documents}
  end

  @impl true
  def handle_call({:open, uri, language_id, version, text}, _from, documents) do
    document = Document.new(uri, language_id, version, text)

    {:reply, :ok, Map.put(documents, uri, document)}
  end

  def handle_call({:replace, uri, version, text}, _from, documents) do
    case Map.fetch(documents, uri) do
      {:ok, document} ->
        updated = Document.replace(document, version, text)

        {:reply, :ok, Map.put(documents, uri, updated)}

      :error ->
        {:reply, {:error, :not_found}, documents}
    end
  end

  def handle_call({:fetch, uri}, _from, documents) do
    {:reply, Map.fetch(documents, uri), documents}
  end

  def handle_call(:open_documents, _from, documents) do
    sorted =
      documents
      |> Map.values()
      |> Enum.sort_by(& &1.uri)

    {:reply, sorted, documents}
  end

  def handle_call({:close, uri}, _from, documents) do
    {:reply, :ok, Map.delete(documents, uri)}
  end
end
