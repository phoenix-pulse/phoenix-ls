defmodule PhoenixLS.Features.PhoenixRequests.Routes do
  @moduledoc """
  Payload builder for route explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload

  @spec list(term()) :: [map()]
  def list(facts) do
    facts
    |> Payload.facts_by_kind(:route)
    |> Enum.map(&Payload.route_payload/1)
    |> Enum.sort_by(&{&1["scopePath"], &1["path"], &1["verb"]})
  end
end
