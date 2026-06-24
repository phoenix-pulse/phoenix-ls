defmodule PhoenixLS.Features.Definition do
  @moduledoc """
  Go-to-definition locations for Phoenix source facts.
  """

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.PhoenixFactLookup
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec definition(CursorContext.t(), [Fact.t()]) :: Location.t() | nil
  def definition(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> location()
  end

  defp location(nil), do: nil

  defp location(%Fact{} = fact) do
    %Location{
      uri: fact.uri,
      range: fact.range
    }
  end
end
