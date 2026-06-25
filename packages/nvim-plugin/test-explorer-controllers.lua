package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

local rendered_lines = {}
local requests = {}

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
      table.insert(requests, method)

      local responses = {
        ["phoenix/listSchemas"] = {},
        ["phoenix/listComponents"] = {},
        ["phoenix/listRoutes"] = {},
        ["phoenix/listEvents"] = {},
        ["phoenix/listTemplates"] = {},
        ["phoenix/listLiveView"] = {},
        ["phoenix/listControllers"] = {
          {
            name = "AppWeb.ProductController",
            module = "AppWeb.ProductController",
            filePath = "/workspace/lib/app_web/controllers/product_controller.ex",
            location = { line = 3, character = 2 },
            actions = {
              {
                name = "show",
                arity = 2,
                filePath = "/workspace/lib/app_web/controllers/product_controller.ex",
                location = { line = 8, character = 2 },
                routes = {
                  {
                    verb = "get",
                    path = "/products/:id",
                    helperBase = "product",
                    filePath = "/workspace/lib/app_web/router.ex",
                    location = { line = 12, character = 4 },
                  },
                },
                renders = {
                  {
                    template = "show",
                    format = "html",
                    templatePath = "/workspace/lib/app_web/controllers/product_html/show.html.heex",
                    templateLocation = { line = 0, character = 0 },
                    assigns = { "product" },
                    confidence = "exact",
                    filePath = "/workspace/lib/app_web/controllers/product_controller.ex",
                    location = { line = 11, character = 6 },
                  },
                },
                assigns = {
                  {
                    name = "product",
                    source = "assign",
                    confidence = "exact",
                    filePath = "/workspace/lib/app_web/controllers/product_controller.ex",
                    location = { line = 9, character = 8 },
                  },
                },
                layouts = {},
              },
            },
            plugAssigns = {
              {
                name = "current_account",
                plug = "load_account",
                confidence = "medium",
                filePath = "/workspace/lib/app_web/controllers/product_controller.ex",
                location = { line = 16, character = 4 },
              },
            },
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
explorer.state.expanded.controllers = true
explorer.state.expanded_items["controller:AppWeb.ProductController"] = true
explorer.state.expanded_items["controller-action:AppWeb.ProductController:show"] = true

explorer.refresh()

assert_contains(requests, "phoenix/listControllers", "controller request")
assert_line_contains(rendered_lines, "Controllers (1)", "controller category")
assert_line_contains(rendered_lines, "AppWeb.ProductController", "controller module")
assert_line_contains(rendered_lines, "show/2", "controller action")
assert_line_contains(rendered_lines, "GET /products/:id", "controller route")
assert_line_contains(rendered_lines, "render :show.html", "controller render")
assert_line_contains(rendered_lines, "@product", "controller assign")
assert_line_contains(rendered_lines, "@current_account", "plug assign")
