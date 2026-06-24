defmodule PhoenixLS.LSP.StatusNotification do
  @moduledoc """
  PhoenixLS structured status notification.
  """

  import Schematic, warn: false

  @derive Jason.Encoder
  defstruct method: "phoenix/status", jsonrpc: "2.0", params: %{}

  @type t :: %__MODULE__{
          method: String.t(),
          jsonrpc: String.t(),
          params: map()
        }

  @spec schema() :: Schematic.t()
  def schema do
    schema(__MODULE__, %{
      method: "phoenix/status",
      jsonrpc: "2.0",
      params: GenLSP.TypeAlias.LSPAny.schema()
    })
  end
end
