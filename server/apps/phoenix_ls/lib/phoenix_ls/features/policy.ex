defmodule PhoenixLS.Features.Policy do
  @moduledoc """
  Central feature policy for resolved Phoenix LS runtime modes.
  """

  alias PhoenixLS.LSP.ServerConfig

  @companion_feature_kinds MapSet.new([
                             :phoenix,
                             :component,
                             :component_attr,
                             :component_slot,
                             :route,
                             :schema,
                             :template,
                             :live_view,
                             :upload,
                             :hook,
                             :colocated_asset,
                             :navigation,
                             :heex_structure
                           ])

  @spec allow?(atom(), atom(), ServerConfig.t()) :: boolean()
  def allow?(_request_kind, feature_kind, %ServerConfig{resolved_mode: :companion}) do
    MapSet.member?(@companion_feature_kinds, feature_kind)
  end

  def allow?(_request_kind, _feature_kind, %ServerConfig{resolved_mode: :full}), do: true
end
