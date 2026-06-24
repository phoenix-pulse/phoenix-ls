defmodule PhoenixLS.Index.Invalidation do
  @moduledoc """
  Explicit invalidation operations for project-scoped index facts.
  """

  alias PhoenixLS.Index.Store

  @spec invalidate_uri(Store.server(), String.t()) :: :ok
  def invalidate_uri(index_store, uri) when is_binary(uri) do
    Store.delete_uri(index_store, uri)
  end
end
