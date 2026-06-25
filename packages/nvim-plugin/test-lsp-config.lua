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

local request_seen = false
local callback_seen = false

vim.lsp.get_clients = function(filter)
  if filter.name ~= "phoenix_pulse" then
    error("expected phoenix_pulse client filter", 2)
  end

  return {
    {
      request = function(self, command, params, callback, bufnr)
        if type(self) ~= "table" then
          error("expected method-style client request", 2)
        end

        if command ~= "phoenix/listSchemas" then
          error("expected phoenix/listSchemas request", 2)
        end

        if params.scope ~= "workspace" then
          error("expected request params to be forwarded", 2)
        end

        if bufnr ~= 0 then
          error("expected current buffer request", 2)
        end

        request_seen = true
        callback(nil, { { name = "App.Catalog.Product" } })
      end,
    },
  }
end

vim.lsp.get_active_clients = function()
  error("expected vim.lsp.get_clients when available", 2)
end

lsp.call_lsp_command("phoenix/listSchemas", { scope = "workspace" }, function(result)
  if result[1].name ~= "App.Catalog.Product" then
    error("expected LSP result to reach callback", 2)
  end

  callback_seen = true
end)

if not request_seen then
  error("expected client request to be sent", 2)
end

if not callback_seen then
  error("expected callback to be called", 2)
end
