defmodule PhoenixLS.LSP.CustomRequest do
  @moduledoc """
  Local representation for non-standard editor requests.
  """

  @enforce_keys [:id, :method]
  defstruct [:id, :method, params: %{}]

  @type t :: %__MODULE__{
          id: integer() | String.t(),
          method: String.t(),
          params: map()
        }
end
