defmodule PhoenixLS.Index.Fact do
  @moduledoc """
  Source-backed fact stored in a project index.
  """

  @enforce_keys [:kind, :id, :uri, :range, :provenance]
  defstruct [:kind, :id, :uri, :range, :provenance, data: %{}]

  @type t :: %__MODULE__{
          kind: atom(),
          id: term(),
          uri: String.t(),
          range: GenLSP.Structures.Range.t(),
          provenance: map(),
          data: map()
        }

  @required_fields [:kind, :id, :uri, :range, :provenance]

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    Enum.each(@required_fields, fn field ->
      if missing?(attrs, field) do
        raise ArgumentError, "index fact requires #{field}"
      end
    end)

    %__MODULE__{
      kind: attrs.kind,
      id: attrs.id,
      uri: attrs.uri,
      range: attrs.range,
      provenance: attrs.provenance,
      data: Map.get(attrs, :data, %{})
    }
  end

  @spec key(t()) :: {atom(), String.t(), term()}
  def key(%__MODULE__{kind: kind, uri: uri, id: id}) do
    {kind, uri, id}
  end

  defp missing?(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> is_nil(value)
      :error -> true
    end
  end
end
