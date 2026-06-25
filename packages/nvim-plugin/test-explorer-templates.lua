package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

local rendered_lines = {}

package.preload["phoenix-pulse.ui"] = function()
  return {
    render_lines = function(_, lines)
      rendered_lines = lines
    end,
  }
end

local requests = {}

package.preload["phoenix-pulse.lsp"] = function()
  return {
    call_lsp_command = function(method, _, callback)
      table.insert(requests, method)

      local responses = {
        ["phoenix/listSchemas"] = {},
        ["phoenix/listComponents"] = {},
        ["phoenix/listRoutes"] = {},
        ["phoenix/listEvents"] = {},
        ["phoenix/listLiveView"] = {},
        ["phoenix/listTemplates"] = {
          {
            name = "index.html",
            format = "heex",
            filePath = "/workspace/lib/app_web/controllers/page_html/index.html.heex",
            location = { line = 0, character = 0 },
          },
        },
      }

      callback(responses[method] or {})
    end,
  }
end

package.preload["phoenix-pulse.icons"] = function()
  return {
    get_icon = function(category)
      return "[" .. category .. "]"
    end,
  }
end

vim = {
  log = { levels = { WARN = 1, INFO = 2 } },
  notify = function() end,
  cmd = function() end,
  api = {
    nvim_buf_is_valid = function()
      return true
    end,
    nvim_buf_call = function(_, callback)
      callback()
    end,
  },
}

local explorer = require("phoenix-pulse.explorer")

local function assert_contains(values, expected, label)
  for _, value in ipairs(values) do
    if value == expected then
      return
    end
  end

  error(string.format("%s: expected %s", label, expected), 2)
end

local function assert_line_contains(lines, expected, label)
  for _, line in ipairs(lines) do
    if string.find(line, expected, 1, true) then
      return
    end
  end

  error(string.format("%s: expected rendered line containing %s", label, expected), 2)
end

explorer.state.buf = 1
explorer.state.win = 1
explorer.state.expanded.templates = true

explorer.refresh()

assert_contains(requests, "phoenix/listTemplates", "template request")
assert_line_contains(rendered_lines, "Templates (1)", "template category")
assert_line_contains(rendered_lines, "index.html", "template item")
