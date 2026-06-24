defmodule PhoenixLS.Workspace.Document do
  @moduledoc """
  Open editor document tracked by the language server.
  """

  @enforce_keys [:uri, :language_id, :version, :text]
  defstruct [:uri, :language_id, :version, :text]

  @type t :: %__MODULE__{
          uri: String.t(),
          language_id: String.t(),
          version: integer(),
          text: String.t()
        }

  @spec new(String.t(), String.t(), integer(), String.t()) :: t()
  def new(uri, language_id, version, text) do
    %__MODULE__{
      uri: uri,
      language_id: language_id,
      version: version,
      text: text
    }
  end

  @spec replace(t(), integer(), String.t()) :: t()
  def replace(%__MODULE__{} = document, version, text) do
    %{document | version: version, text: text}
  end
end
