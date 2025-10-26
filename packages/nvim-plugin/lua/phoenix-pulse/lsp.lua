-- Phoenix Pulse LSP Client Configuration

local M = {}

function M.setup(config)
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
        cmd = { "node", config.lsp_server_path, "--stdio" },
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
  local clients = vim.lsp.get_active_clients({ name = "phoenix_pulse" })

  if #clients == 0 then
    vim.notify("[Phoenix Pulse] LSP server not running", vim.log.levels.WARN)
    return
  end

  local client = clients[1]

  client.request(command, params or {}, function(err, result)
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
