defmodule PhoenixLS.Index.Indexer do
  @moduledoc """
  Background worker for project-scoped indexing jobs.
  """

  use GenServer

  alias PhoenixLS.Index.{DocumentIndexer, Invalidation}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.Document

  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec schedule_document(server(), Document.t()) :: :ok
  def schedule_document(server, %Document{} = document) do
    GenServer.cast(server, {:index_document, document})
  end

  @spec schedule_uri(server(), String.t()) :: :ok
  def schedule_uri(server, uri) when is_binary(uri) do
    GenServer.cast(server, {:index_uri, uri})
  end

  @spec delete_uri(server(), String.t()) :: :ok
  def delete_uri(server, uri) when is_binary(uri) do
    GenServer.cast(server, {:delete_uri, uri})
  end

  @impl true
  def init(opts) do
    index_store = Keyword.fetch!(opts, :index_store)

    {:ok, %{index_store: index_store}}
  end

  @impl true
  def handle_cast({:index_document, document}, state) do
    _result = DocumentIndexer.index(state.index_store, document)

    {:noreply, state}
  end

  def handle_cast({:index_uri, uri}, state) do
    index_uri(state.index_store, uri)

    {:noreply, state}
  end

  def handle_cast({:delete_uri, uri}, state) do
    :ok = Invalidation.invalidate_uri(state.index_store, uri)

    {:noreply, state}
  end

  defp index_uri(index_store, uri) do
    with {:ok, path} <- SupportURI.file_uri_to_path(uri),
         true <- elixir_path?(path),
         {:ok, text} <- File.read(path) do
      document = Document.new(uri, "elixir", 0, text)
      _result = DocumentIndexer.index(index_store, document)
      :ok
    else
      _ignored -> :ok
    end
  end

  defp elixir_path?(path), do: Path.extname(path) == ".ex"
end
