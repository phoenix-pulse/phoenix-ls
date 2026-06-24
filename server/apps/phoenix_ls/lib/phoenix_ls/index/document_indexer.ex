defmodule PhoenixLS.Index.DocumentIndexer do
  @moduledoc """
  Indexes open editor documents into a project index store.
  """

  alias PhoenixLS.Index.{ElixirSource, Store}
  alias PhoenixLS.Workspace.Document

  @spec index(Store.server(), Document.t()) :: :ok | :ignored | {:error, {:parse_error, term()}}
  def index(index_store, %Document{} = document) do
    if elixir_document?(document) do
      reindex_elixir(index_store, document)
    else
      :ignored
    end
  end

  @spec delete_uri(Store.server(), String.t()) :: :ok
  def delete_uri(index_store, uri) when is_binary(uri) do
    Store.delete_uri(index_store, uri)
  end

  defp reindex_elixir(index_store, document) do
    :ok = Store.delete_uri(index_store, document.uri)

    case ElixirSource.facts(document.uri, document.text, version: document.version) do
      {:ok, facts} ->
        Enum.each(facts, &Store.put(index_store, &1))

        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp elixir_document?(%Document{language_id: "elixir"}), do: true

  defp elixir_document?(%Document{uri: uri}) do
    String.ends_with?(uri, ".ex")
  end
end
