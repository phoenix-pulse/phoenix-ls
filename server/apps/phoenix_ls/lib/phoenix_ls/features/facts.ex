defmodule PhoenixLS.Features.Facts do
  @moduledoc """
  Small helpers for querying feature fact lists.
  """

  alias PhoenixLS.Index.Fact

  @spec by_kind([Fact.t()], atom()) :: [Fact.t()]
  def by_kind(facts, kind) when is_list(facts) and is_atom(kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end
end
