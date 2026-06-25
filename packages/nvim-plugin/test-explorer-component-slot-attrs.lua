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
        ["phoenix/listComponents"] = {
          {
            name = "table",
            module = "AppWeb.CoreComponents",
            filePath = "/workspace/lib/app_web/components/core_components.ex",
            location = { line = 20, character = 2 },
            attributes = {},
            slots = {
              {
                name = "col",
                required = false,
                filePath = "/workspace/lib/app_web/components/core_components.ex",
                location = { line = 31, character = 2 },
                attributes = {
                  {
                    name = "label",
                    type = "string",
                    required = true,
                    filePath = "/workspace/lib/app_web/components/core_components.ex",
                    location = { line = 32, character = 4 },
                  },
                },
              },
            },
          },
        },
        ["phoenix/listRoutes"] = {},
        ["phoenix/listEvents"] = {},
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
explorer.state.expanded.components = true
explorer.state.expanded_items["component:/workspace/lib/app_web/components/core_components.ex:table"] = true
explorer.state.expanded_items["component-slot:/workspace/lib/app_web/components/core_components.ex:table:col"] = true

explorer.refresh()

assert_line_contains(rendered_lines, ":col", "component slot")
assert_line_contains(rendered_lines, "label: :string", "component slot attr")

local slot_attr_target = explorer._definition_target({
  component = explorer.state.data.components[1],
  slot = explorer.state.data.components[1].slots[1],
  attribute = explorer.state.data.components[1].slots[1].attributes[1],
})

assert_equal(slot_attr_target.file, "/workspace/lib/app_web/components/core_components.ex", "slot attr target file")
assert_equal(slot_attr_target.line, 33, "slot attr target line")
