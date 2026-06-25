-- Phoenix Pulse LSP Client Configuration

local M = {}

local function bool_env(value)
  return value and "1" or "0"
end

local function companion_config(config)
  return config.companion or {}
end

local function mode(config)
  return config.mode or "auto"
end

local function disable_generic_elixir(config)
  local companion = companion_config(config)
  return companion.disable_generic_elixir ~= false
end

local function filter_clients_by_name(clients, name)
  if type(clients) ~= "table" then
    return {}
  end

  local matches = {}

  for _, client in ipairs(clients) do
    if client.name == name then
      table.insert(matches, client)
    end
  end

  return matches
end

local function get_lsp_clients(name)
  if not vim.lsp then
    return {}
  end

  local getter = vim.lsp.get_clients or vim.lsp.get_active_clients

  if not getter then
    return {}
  end

  local ok, clients = pcall(getter, { name = name })

  if ok then
    return filter_clients_by_name(clients, name)
  end

  ok, clients = pcall(getter)

  if not ok then
    return {}
  end

  return filter_clients_by_name(clients, name)
end

local function is_lsp_enabled(name)
  if not vim.lsp or type(vim.lsp.is_enabled) ~= "function" then
    return false
  end

  local ok, enabled = pcall(vim.lsp.is_enabled, name)
  return ok and enabled == true
end

local function is_expert_configured(lspconfig, configs)
  if type(configs.expert) == "table" then
    return true
  end

  if is_lsp_enabled("expert") then
    return true
  end

  local expert = rawget(lspconfig, "expert")
  return type(expert) == "table" and (expert.manager ~= nil or expert.document_config ~= nil)
end

local function detected_expert(config, lspconfig, configs)
  local companion = companion_config(config)

  if companion.detect_expert == false then
    return false
  end

  if #get_lsp_clients("expert") > 0 then
    return true
  end

  return is_expert_configured(lspconfig, configs)
end

local function server_env(config, lspconfig, configs)
  return {
    PHOENIX_LS_SOURCE_ONLY = bool_env(config.source_only_mode),
    PHOENIX_LS_LOG_LEVEL = config.log_level or "info",
    PHOENIX_LS_INDEXING = bool_env(config.indexing_enabled),
    PHOENIX_LS_COMPILATION = bool_env(config.compilation_enabled),
    PHOENIX_LS_MODE = mode(config),
    PHOENIX_LS_DETECTED_EXPERT = bool_env(detected_expert(config, lspconfig, configs)),
    PHOENIX_LS_DISABLE_GENERIC_ELIXIR = bool_env(disable_generic_elixir(config)),
  }
end

function M.setup(config)
  config = config or {}

  -- Check if lspconfig is available
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    vim.notify(
      "[Phoenix Pulse] nvim-lspconfig not found. Please install it first.",
      vim.log.levels.ERROR
    )
    return
  end

  local configs = require("lspconfig.configs")

  -- Register phoenix_pulse LSP server if not already registered
  if not configs.phoenix_pulse then
    configs.phoenix_pulse = {
      default_config = {
        cmd = { config.lsp_server_path, "--stdio" },
        cmd_env = server_env(config, lspconfig, configs),
        filetypes = { "elixir", "heex", "eelixir" },
        root_dir = function(fname)
          return lspconfig.util.root_pattern("mix.exs", ".git")(fname)
        end,
        settings = {},
        name = "phoenix_pulse",
      },
    }
  end

  -- Setup phoenix_pulse LSP
  lspconfig.phoenix_pulse.setup({
    on_attach = function(client, bufnr)
      -- Enable completion
      vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

      -- Keybindings for LSP features
      local bufopts = { noremap = true, silent = true, buffer = bufnr }
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
      vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
      vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
      vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
      vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, bufopts)
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, bufopts)
      vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)

      -- Silent attach - only log to LSP log, not user notifications
    end,

    on_init = function(client)
      -- Only notify once when LSP server starts (not per file)
      vim.notify("[Phoenix Pulse] LSP server ready", vim.log.levels.INFO)
    end,

    capabilities = vim.lsp.protocol.make_client_capabilities(),
  })
end

-- Helper function to call custom LSP commands
function M.call_lsp_command(command, params, callback)
  local clients

  if vim.lsp.get_clients then
    clients = vim.lsp.get_clients({ name = "phoenix_pulse" })
  else
    clients = vim.lsp.get_active_clients({ name = "phoenix_pulse" })
  end

  if #clients == 0 then
    vim.notify("[Phoenix Pulse] LSP server not running", vim.log.levels.WARN)
    return
  end

  local client = clients[1]

  client:request(command, params or {}, function(err, result)
    if err then
      vim.notify(
        "[Phoenix Pulse] LSP command error: " .. vim.inspect(err),
        vim.log.levels.ERROR
      )
      return
    end

    if callback then
      callback(result)
    end
  end, 0)
end

return M
