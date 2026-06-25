defmodule PhoenixLS.Features.PolicyTest do
  use ExUnit.Case, async: true

  import PhoenixLS.Support.LSPConfigHelpers, only: [companion_config: 0, full_config: 0]

  alias PhoenixLS.Features.Policy

  test "allows Phoenix-specific and shared features in companion mode" do
    assert Policy.allow?(:completion, :component_attr, companion_config())
    assert Policy.allow?(:hover, :route, companion_config())
    assert Policy.allow?(:diagnostic, :phoenix, companion_config())
  end

  test "allows every planned companion feature kind in companion mode" do
    allowed_feature_kinds = [
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
    ]

    for feature_kind <- allowed_feature_kinds do
      assert Policy.allow?(:completion, feature_kind, companion_config())
    end
  end

  test "denies generic Expert-owned features in companion mode" do
    refute Policy.allow?(:completion, :generic_elixir, companion_config())
    refute Policy.allow?(:hover, :generic_elixir, companion_config())
    refute Policy.allow?(:diagnostic, :compiler, companion_config())

    for feature_kind <- [:formatting, :references, :rename, :workspace_symbol] do
      refute Policy.allow?(:completion, feature_kind, companion_config())
    end
  end

  test "denies unknown feature kinds in companion mode" do
    refute Policy.allow?(:completion, :unclassified_feature, companion_config())
  end

  test "allows generic and unknown feature kinds in full mode" do
    assert Policy.allow?(:completion, :generic_elixir, full_config())
    assert Policy.allow?(:completion, :unclassified_feature, full_config())
  end

  test "uses resolved mode instead of requested mode" do
    config = %{companion_config() | mode: :full}

    refute Policy.allow?(:completion, :generic_elixir, config)
  end
end
