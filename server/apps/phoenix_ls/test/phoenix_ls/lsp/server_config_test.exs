defmodule PhoenixLS.LSP.ServerConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.ServerConfig

  test "builds the default runtime config" do
    assert %ServerConfig{
             source_only?: true,
             project_indexing_enabled?: true,
             project_compilation_enabled?: false,
             log_level: :info,
             mode: :auto,
             resolved_mode: :full,
             detected_expert?: false,
             detected_companion_peer?: false,
             disable_generic_elixir?: true
           } = ServerConfig.default()
  end

  test "defaults to source-only project indexing with info logging" do
    assert %ServerConfig{
             source_only?: true,
             project_indexing_enabled?: true,
             project_compilation_enabled?: false,
             log_level: :info,
             mode: :auto,
             resolved_mode: :full,
             detected_expert?: false,
             detected_companion_peer?: false,
             disable_generic_elixir?: true
           } = ServerConfig.from_env(%{})
  end

  test "reads editor runtime flags from the environment" do
    assert %ServerConfig{
             source_only?: false,
             project_indexing_enabled?: false,
             project_compilation_enabled?: true,
             log_level: :warning,
             mode: :companion,
             resolved_mode: :companion,
             detected_expert?: true,
             detected_companion_peer?: true,
             disable_generic_elixir?: false
           } =
             ServerConfig.from_env(%{
               "PHOENIX_LS_SOURCE_ONLY" => "0",
               "PHOENIX_LS_INDEXING" => "false",
               "PHOENIX_LS_COMPILATION" => "true",
               "PHOENIX_LS_LOG_LEVEL" => "warn",
               "PHOENIX_LS_MODE" => " companion ",
               "PHOENIX_LS_DETECTED_EXPERT" => "true",
               "PHOENIX_LS_DISABLE_GENERIC_ELIXIR" => "false"
             })
  end

  test "resolves automatic mode from detected Expert environment flag" do
    assert %ServerConfig{
             mode: :auto,
             resolved_mode: :companion,
             detected_expert?: true,
             detected_companion_peer?: true
           } =
             ServerConfig.from_env(%{
               "PHOENIX_LS_MODE" => "auto",
               "PHOENIX_LS_DETECTED_EXPERT" => "true"
             })
  end

  test "resolves automatic mode from detected companion peer environment flag" do
    assert %ServerConfig{
             mode: :auto,
             resolved_mode: :companion,
             detected_expert?: false,
             detected_companion_peer?: true
           } =
             ServerConfig.from_env(%{
               "PHOENIX_LS_MODE" => "auto",
               "PHOENIX_LS_DETECTED_EXPERT" => "false",
               "PHOENIX_LS_DETECTED_COMPANION_PEER" => "true"
             })
  end

  test "falls back to automatic mode for unknown mode values" do
    assert %ServerConfig{
             mode: :auto,
             resolved_mode: :full
           } = ServerConfig.from_env(%{"PHOENIX_LS_MODE" => "invalid"})
  end

  test "builds project manager options from runtime config" do
    config = %ServerConfig{
      source_only?: true,
      project_indexing_enabled?: false,
      project_compilation_enabled?: false,
      log_level: :info,
      mode: :auto,
      resolved_mode: :full,
      detected_expert?: false,
      detected_companion_peer?: false,
      disable_generic_elixir?: true
    }

    assert ServerConfig.project_manager_opts(config, self()) == [
             status_target: self(),
             source_only?: true,
             project_indexing_enabled: false,
             project_compilation_enabled: false
           ]
  end

  test "passes compilation-aware mode through project manager options" do
    config = %ServerConfig{
      source_only?: false,
      project_indexing_enabled?: true,
      project_compilation_enabled?: true,
      log_level: :info,
      mode: :full,
      resolved_mode: :full,
      detected_expert?: true,
      detected_companion_peer?: true,
      disable_generic_elixir?: true
    }

    assert ServerConfig.project_manager_opts(config, self()) == [
             status_target: self(),
             source_only?: false,
             project_indexing_enabled: true,
             project_compilation_enabled: true
           ]
  end
end
