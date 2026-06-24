defmodule PhoenixLS.Index.Snapshot do
  @moduledoc """
  Immutable read model for indexed project facts.
  """

  alias PhoenixLS.Index.{Fact, Store}

  @enforce_keys [:facts, :by_kind]
  defstruct [:facts, :by_kind]

  @type t :: %__MODULE__{
          facts: [Fact.t()],
          by_kind: %{optional(atom()) => [Fact.t()]}
        }

  @spec empty() :: t()
  def empty do
    new([])
  end

  @spec from_store(Store.server()) :: t()
  def from_store(store) do
    store
    |> Store.all()
    |> new()
  end

  @spec new([Fact.t()]) :: t()
  def new(facts) when is_list(facts) do
    %__MODULE__{
      facts: facts,
      by_kind: Enum.group_by(facts, & &1.kind)
    }
  end

  @spec all(t()) :: [Fact.t()]
  def all(%__MODULE__{facts: facts}), do: facts

  @spec by_kind(t(), atom()) :: [Fact.t()]
  def by_kind(%__MODULE__{by_kind: by_kind}, kind) when is_atom(kind) do
    Map.get(by_kind, kind, [])
  end
end
