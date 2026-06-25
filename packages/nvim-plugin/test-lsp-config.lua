package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

local captured_setup = nil
local configs = {}

local lspconfig = {
  util = {
    root_pattern = function()
      return function()
        return "/workspace"
      end
    end,
  },
  phoenix_pulse = {
    setup = function(opts)
      captured_setup = opts
    end,
  },
}

package.preload["lspconfig"] = function()
  return lspconfig
end

package.preload["lspconfig.configs"] = function()
  return configs
end

vim = {
  log = { levels = { ERROR = 1, INFO = 2 } },
  notify = function() end,
  lsp = {
    protocol = {
      make_client_capabilities = function()
        return {}
      end,
    },
  },
}

local lsp = require("phoenix-pulse.lsp")

lsp.setup({
  lsp_server_path = "/tmp/phoenix_ls",
  source_only_mode = false,
  log_level = "debug",
  indexing_enabled = false,
  compilation_enabled = true,
})

local default_config = configs.phoenix_pulse and configs.phoenix_pulse.default_config

if not default_config then
  error("expected phoenix_pulse default_config to be registered", 2)
end

if default_config.cmd[1] ~= "/tmp/phoenix_ls" or default_config.cmd[2] ~= "--stdio" then
  error("expected phoenix_pulse to start the configured Elixir executable", 2)
end

local env = default_config.cmd_env or {}

if env.PHOENIX_LS_SOURCE_ONLY ~= "0" then
  error("expected PHOENIX_LS_SOURCE_ONLY=0", 2)
end

if env.PHOENIX_LS_LOG_LEVEL ~= "debug" then
  error("expected PHOENIX_LS_LOG_LEVEL=debug", 2)
end

if env.PHOENIX_LS_INDEXING ~= "0" then
  error("expected PHOENIX_LS_INDEXING=0", 2)
end

if env.PHOENIX_LS_COMPILATION ~= "1" then
  error("expected PHOENIX_LS_COMPILATION=1", 2)
end

if type(captured_setup) ~= "table" then
  error("expected lspconfig setup to be called", 2)
end
