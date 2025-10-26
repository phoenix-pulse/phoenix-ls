-- Phoenix Pulse Plugin Entry Point
-- This file is automatically loaded by Neovim

-- Prevent loading twice
if vim.g.loaded_phoenix_pulse then
  return
end
vim.g.loaded_phoenix_pulse = true

-- The plugin is loaded, but setup() must be called explicitly by the user
-- in their config with require("phoenix-pulse").setup({})
