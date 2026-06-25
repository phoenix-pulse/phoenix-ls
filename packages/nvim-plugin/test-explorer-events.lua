package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

local rendered_lines = {}

package.preload["phoenix-pulse.ui"] = function()
  return {
    render_lines = function(_, lines)
      rendered_lines = lines
    end,
  }
end

package.preload["phoenix-pulse.lsp"] = function()
  return {
    call_lsp_command = function(method, _, callback)
      local responses = {
        ["phoenix/listSchemas"] = {},
        ["phoenix/listComponents"] = {},
        ["phoenix/listRoutes"] = {},
        ["phoenix/listEvents"] = {
          {
            name = "save",
            type = "handle_event",
            handler = "handle_event/3",
            arity = 3,
            module = "AppWeb.ProductLive.Index",
            filePath = "/workspace/lib/app_web/live/product_live/index.ex",
            location = { line = 48, character = 4 },
          },
        },
        ["phoenix/listTemplates"] = {},
        ["phoenix/listLiveView"] = {},
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

local function assert_line_contains(lines, expected, label)
  for _, line in ipairs(lines) do
    if string.find(line, expected, 1, true) then
      return
    end
  end

  error(string.format("%s: expected rendered line containing %s", label, expected), 2)
end

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

explorer.state.buf = 1
explorer.state.win = 1
explorer.state.expanded.events = true

explorer.refresh()

assert_line_contains(rendered_lines, "Events (1)", "event category")
assert_line_contains(rendered_lines, "save (AppWeb.ProductLive.Index - handle_event/3)", "event module context")

local target = explorer._definition_target(explorer.state.data.events[1])
assert_equal(target.file, "/workspace/lib/app_web/live/product_live/index.ex", "event target file")
assert_equal(target.line, 49, "event target line")
