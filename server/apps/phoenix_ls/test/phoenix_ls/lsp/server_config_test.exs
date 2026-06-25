defmodule PhoenixLS.LSP.ServerConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.ServerConfig

  test "defaults to source-only project indexing with info logging" do
    assert %ServerConfig{
             source_only?: true,
             project_indexing_enabled?: true,
             log_level: :info
           } = ServerConfig.from_env(%{})
  end

  test "reads editor runtime flags from the environment" do
    assert %ServerConfig{
             source_only?: false,
             project_indexing_enabled?: false,
             log_level: :warning
           } =
             ServerConfig.from_env(%{
               "PHOENIX_LS_SOURCE_ONLY" => "0",
               "PHOENIX_LS_INDEXING" => "false",
               "PHOENIX_LS_LOG_LEVEL" => "warn"
             })
  end

  test "builds project manager options from runtime config" do
    config = %ServerConfig{source_only?: true, project_indexing_enabled?: false, log_level: :info}

    assert ServerConfig.project_manager_opts(config, self()) == [
             status_target: self(),
             project_indexing_enabled: false
           ]
  end
end
