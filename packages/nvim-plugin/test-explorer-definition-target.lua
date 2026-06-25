package.path = "packages/nvim-plugin/lua/?.lua;packages/nvim-plugin/lua/?/init.lua;" .. package.path

package.preload["phoenix-pulse.ui"] = function()
  return {}
end

package.preload["phoenix-pulse.lsp"] = function()
  return {}
end

package.preload["phoenix-pulse.icons"] = function()
  return {
    get_icon = function()
      return ""
    end,
  }
end

vim = {
  log = { levels = { WARN = 1, INFO = 2 } },
  notify = function() end,
}

local explorer = require("phoenix-pulse.explorer")

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local schema = {
  filePath = "/workspace/lib/app/catalog/product.ex",
  location = { line = 10, character = 2 },
}

local field = {
  filePath = "/workspace/lib/app/catalog/product.ex",
  location = { line = 14, character = 4 },
}

local field_target = explorer._definition_target({ schema = schema, field = field })
assert_equal(field_target.file, field.filePath, "schema field file")
assert_equal(field_target.line, 15, "schema field line")

local association = {
  filePath = "/workspace/lib/app/catalog/product.ex",
  location = { line = 18, character = 4 },
}

local association_target = explorer._definition_target({ schema = schema, association = association })
assert_equal(association_target.file, association.filePath, "schema association file")
assert_equal(association_target.line, 19, "schema association line")

local component = {
  filePath = "/workspace/lib/app_web/components/core_components.ex",
  location = { line = 30, character = 2 },
}

local attribute = {
  filePath = "/workspace/lib/app_web/components/core_components.ex",
  location = { line = 22, character = 2 },
}

local attribute_target = explorer._definition_target({ component = component, attribute = attribute })
assert_equal(attribute_target.file, attribute.filePath, "component attribute file")
assert_equal(attribute_target.line, 23, "component attribute line")

local slot = {
  filePath = "/workspace/lib/app_web/components/core_components.ex",
  location = { line = 25, character = 2 },
}

local slot_target = explorer._definition_target({ component = component, slot = slot })
assert_equal(slot_target.file, slot.filePath, "component slot file")
assert_equal(slot_target.line, 26, "component slot line")

local liveview_module = {
  filePath = "/workspace/lib/app_web/live/product_live/index.ex",
  location = { line = 5, character = 2 },
}

local liveview_function = {
  filePath = "/workspace/lib/app_web/live/product_live/events.ex",
  location = { line = 48, character = 4 },
}

local function_target = explorer._definition_target({ module = liveview_module, func = liveview_function })
assert_equal(function_target.file, liveview_function.filePath, "LiveView function file")
assert_equal(function_target.line, 49, "LiveView function line")
