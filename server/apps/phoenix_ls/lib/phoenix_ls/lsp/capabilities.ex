defmodule PhoenixLS.LSP.Capabilities do
  @moduledoc """
  Builds LSP server capabilities for the clean v2 server.

  Capabilities must not get ahead of implemented handlers. Add a capability
  only in the same change that handles the corresponding request or
  notification.
  """

  alias GenLSP.Structures.ServerCapabilities

  def build do
    %ServerCapabilities{}
  end
end
