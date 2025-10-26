-- Phoenix Pulse User Commands

local M = {}

function M.setup(config)
  -- Command: Toggle project explorer
  vim.api.nvim_create_user_command("PhoenixPulseToggle", function()
    require("phoenix-pulse.explorer").toggle()
  end, { desc = "Toggle Phoenix Pulse Explorer" })

  -- Command: Open explorer as floating window
  vim.api.nvim_create_user_command("PhoenixPulseExplorerFloat", function()
    require("phoenix-pulse.explorer").open("float")
  end, { desc = "Open Phoenix Pulse Explorer (Float)" })

  -- Command: Open explorer as split window
  vim.api.nvim_create_user_command("PhoenixPulseExplorerSplit", function()
    require("phoenix-pulse.explorer").open("split")
  end, { desc = "Open Phoenix Pulse Explorer (Split)" })

  -- Command: Show ERD diagram
  vim.api.nvim_create_user_command("PhoenixPulseERD", function()
    require("phoenix-pulse.erd").show()
  end, { desc = "Show Phoenix Pulse ERD Diagram" })

  -- Command: Generate ERD Mermaid file only
  vim.api.nvim_create_user_command("PhoenixPulseERDMermaid", function()
    require("phoenix-pulse.erd").generate_mermaid()
  end, { desc = "Generate Phoenix Pulse ERD Mermaid File" })

  -- Command: List all schemas
  vim.api.nvim_create_user_command("PhoenixPulseSchemas", function()
    require("phoenix-pulse.lsp").call_lsp_command("phoenix/listSchemas", {}, function(result)
      vim.notify("[Phoenix Pulse] Found " .. #result .. " schemas", vim.log.levels.INFO)
      vim.print(result)
    end)
  end, { desc = "List Phoenix Schemas" })

  -- Command: List all components
  vim.api.nvim_create_user_command("PhoenixPulseComponents", function()
    require("phoenix-pulse.lsp").call_lsp_command("phoenix/listComponents", {}, function(result)
      vim.notify("[Phoenix Pulse] Found " .. #result .. " components", vim.log.levels.INFO)
      vim.print(result)
    end)
  end, { desc = "List Phoenix Components" })

  -- Command: List all routes
  vim.api.nvim_create_user_command("PhoenixPulseRoutes", function()
    require("phoenix-pulse.lsp").call_lsp_command("phoenix/listRoutes", {}, function(result)
      vim.notify("[Phoenix Pulse] Found " .. #result .. " routes", vim.log.levels.INFO)
      vim.print(result)
    end)
  end, { desc = "List Phoenix Routes" })

  -- Command: List all events
  vim.api.nvim_create_user_command("PhoenixPulseEvents", function()
    require("phoenix-pulse.lsp").call_lsp_command("phoenix/listEvents", {}, function(result)
      vim.notify("[Phoenix Pulse] Found " .. #result .. " events", vim.log.levels.INFO)
      vim.print(result)
    end)
  end, { desc = "List Phoenix Events" })

  -- Command: Refresh project explorer
  vim.api.nvim_create_user_command("PhoenixPulseRefresh", function()
    require("phoenix-pulse.explorer").refresh()
  end, { desc = "Refresh Phoenix Pulse Explorer" })
end

return M
