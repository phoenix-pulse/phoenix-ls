defmodule PhoenixLS.Support.LSPConfigHelpers do
  @moduledoc false

  alias PhoenixLS.LSP.ServerConfig

  def server_config(overrides \\ []) do
    ServerConfig.default()
    |> struct!(overrides)
  end

  def full_config do
    server_config()
  end

  def companion_config do
    server_config(
      resolved_mode: :companion,
      detected_expert?: true,
      detected_companion_peer?: true
    )
  end
end
