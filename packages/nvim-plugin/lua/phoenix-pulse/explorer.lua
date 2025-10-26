-- Phoenix Pulse Project Explorer
-- Tree view of schemas, components, routes, events, etc.

local M = {}
local ui = require("phoenix-pulse.ui")
local lsp = require("phoenix-pulse.lsp")
local icons_mod = require("phoenix-pulse.icons")

-- State
M.state = {
  win = nil,
  buf = nil,
  mode = "float",  -- "float" or "split"
  expanded = {
    schemas = true,
    components = true,
    routes = true,
    events = true,
    templates = false,
    controllers = false,
    assets = false,
    liveviews = true,
  },
  expanded_items = {},  -- Track expansion state per unique item ID
  search_query = "",    -- Current search filter
  data = {
    schemas = {},
    components = {},
    routes = {},
    events = {},
    liveviews = {},  -- LiveView modules with functions
    statistics = nil,  -- Computed statistics
  },
  lines = {},       -- Rendered lines
  line_map = {},    -- Maps line number to item (enhanced with depth, id, parent_id)
}

-- Get icon for category
local function get_icon(category)
  return icons_mod.get_icon(category)
end

-- ============================================================================
-- ID Generation Utilities
-- ============================================================================

-- Generate unique ID for category
local function generate_category_id(category)
  return "category:" .. category
end

-- Generate unique ID for schema
local function generate_schema_id(schema)
  return "schema:" .. (schema.name or "unknown")
end

-- Generate unique ID for schema section
local function generate_schema_section_id(schema, section)
  return "schema-section:" .. (schema.name or "unknown") .. ":" .. section
end

-- Generate unique ID for schema field
local function generate_schema_field_id(schema, field)
  return "schema-field:" .. (schema.name or "unknown") .. ":" .. (field.name or "unknown")
end

-- Generate unique ID for schema association
local function generate_schema_assoc_id(schema, assoc)
  return "schema-assoc:" .. (schema.name or "unknown") .. ":" .. (assoc.name or "unknown")
end

-- Generate unique ID for component
local function generate_component_id(component)
  local file = component.filePath or component.file or "unknown"
  return "component:" .. file .. ":" .. (component.name or "unknown")
end

-- Generate unique ID for component attribute
local function generate_component_attr_id(component, attr)
  local file = component.filePath or component.file or "unknown"
  return "component-attr:" .. file .. ":" .. (component.name or "unknown") .. ":" .. (attr.name or "unknown")
end

-- Generate unique ID for component slot
local function generate_component_slot_id(component, slot)
  local file = component.filePath or component.file or "unknown"
  return "component-slot:" .. file .. ":" .. (component.name or "unknown") .. ":" .. (slot.name or "unknown")
end

-- Generate unique ID for route
local function generate_route_id(route)
  local method = route.verb or route.method or "GET"
  local path = route.path or "/"
  return "route:" .. method .. ":" .. path
end

-- Generate unique ID for event
local function generate_event_id(event)
  local file = event.filePath or event.file or "unknown"
  return "event:" .. file .. ":" .. (event.name or "unknown")
end

-- Generate unique ID for template
local function generate_template_id(template)
  local file = template.filePath or template.file or "unknown"
  return "template:" .. file .. ":" .. (template.name or "unknown")
end

-- Generate unique ID for controller
local function generate_controller_id(controller)
  return "controller:" .. (controller.name or "unknown")
end

-- Generate unique ID for asset
local function generate_asset_id(asset)
  return "asset:" .. (asset.publicPath or "unknown")
end

-- Generate unique ID for LiveView folder
local function generate_liveview_folder_id(folder_path)
  return "liveview-folder:" .. folder_path
end

-- Generate unique ID for LiveView module
local function generate_liveview_module_id(module)
  return "liveview-module:" .. (module.module or "unknown")
end

-- Generate unique ID for LiveView function
local function generate_liveview_func_id(module, func)
  return "liveview-func:" .. (module.module or "unknown") .. ":" .. (func.name or "unknown") .. ":" .. (func.type or "unknown")
end

-- Generate unique ID for statistics item
local function generate_statistics_id(stat_type)
  return "statistics:" .. stat_type
end

-- Check if item is expanded
local function is_expanded(id)
  return M.state.expanded_items[id] == true
end

-- Toggle expansion state
local function toggle_expansion(id)
  M.state.expanded_items[id] = not M.state.expanded_items[id]
  M.render()
end

-- ============================================================================
-- End of ID Generation Utilities
-- ============================================================================

-- ============================================================================
-- Hierarchical Rendering Engine
-- ============================================================================

-- Current line number and line_map during rendering
local render_state = {
  current_line = 1,
  lines = {},
  line_map = {}
}

-- Get indentation string based on depth
local function get_indentation(depth)
  return string.rep("  ", depth)
end

-- Add a line to the rendered output with metadata
local function add_line(text, id, depth, item_type, item, parent_id, has_children)
  table.insert(render_state.lines, text)
  render_state.line_map[render_state.current_line] = {
    type = item_type,
    item = item,
    id = id,
    parent_id = parent_id,
    depth = depth,
    has_children = has_children or false
  }
  render_state.current_line = render_state.current_line + 1
end

-- Render schema children (Fields and Associations sections)
local function render_schema_children(schema, parent_id, depth)
  -- Check if schema is expanded
  if not is_expanded(parent_id) then
    return
  end

  -- Render Fields section if there are fields
  if schema.fields and #schema.fields > 0 then
    local fields_section_id = generate_schema_section_id(schema, "fields")
    local fields_expanded_icon = is_expanded(fields_section_id) and "▼" or "▶"
    local fields_line = get_indentation(depth) .. string.format("%s 📋 Fields (%d)", fields_expanded_icon, #schema.fields)
    add_line(fields_line, fields_section_id, depth, "schema-fields-section", schema, parent_id, true)

    -- If fields section is expanded, show individual fields
    if is_expanded(fields_section_id) then
      for _, field in ipairs(schema.fields) do
        local field_id = generate_schema_field_id(schema, field)
        local field_type = field.type or "unknown"
        local field_line = get_indentation(depth + 1) .. string.format("📄 %s: %s", field.name or "unknown", field_type)
        add_line(field_line, field_id, depth + 1, "schema-field", { schema = schema, field = field }, fields_section_id, false)
      end
    end
  end

  -- Render Associations section if there are associations
  if schema.associations and #schema.associations > 0 then
    local assocs_section_id = generate_schema_section_id(schema, "associations")
    local assocs_expanded_icon = is_expanded(assocs_section_id) and "▼" or "▶"
    local assocs_line = get_indentation(depth) .. string.format("%s 🔗 Associations (%d)", assocs_expanded_icon, #schema.associations)
    add_line(assocs_line, assocs_section_id, depth, "schema-associations-section", schema, parent_id, true)

    -- If associations section is expanded, show individual associations
    if is_expanded(assocs_section_id) then
      for _, assoc in ipairs(schema.associations) do
        local assoc_id = generate_schema_assoc_id(schema, assoc)
        local assoc_type = assoc.type or "unknown"
        local assoc_target = assoc.schema or "unknown"
        local assoc_line = get_indentation(depth + 1) .. string.format("🔗 %s :%s", assoc_type, assoc.name or "unknown")
        if assoc_target ~= "unknown" then
          assoc_line = assoc_line .. " → " .. assoc_target
        end
        add_line(assoc_line, assoc_id, depth + 1, "schema-association", { schema = schema, association = assoc }, assocs_section_id, false)
      end
    end
  end
end

-- Render component children (attributes and slots)
local function render_component_children(component, parent_id, depth)
  -- Check if component is expanded
  if not is_expanded(parent_id) then
    return
  end

  -- Render attributes
  if component.attributes and #component.attributes > 0 then
    for _, attr in ipairs(component.attributes) do
      local attr_id = generate_component_attr_id(component, attr)
      local attr_type = attr.rawType or (":" .. (attr.type or "unknown"))
      local attr_line = get_indentation(depth) .. string.format("⚙️ %s: %s", attr.name or "unknown", attr_type)

      -- Add attribute details (required, default, values)
      local details = {}
      if attr.required then table.insert(details, "required") end
      if attr.default then table.insert(details, "default: " .. attr.default) end
      if attr.values and #attr.values > 0 then
        table.insert(details, "values: " .. table.concat(attr.values, ", "))
      end
      if #details > 0 then
        attr_line = attr_line .. " (" .. table.concat(details, ", ") .. ")"
      end

      add_line(attr_line, attr_id, depth, "component-attribute", { component = component, attribute = attr }, parent_id, false)
    end
  end

  -- Render slots
  if component.slots and #component.slots > 0 then
    for _, slot in ipairs(component.slots) do
      local slot_id = generate_component_slot_id(component, slot)
      local slot_line = get_indentation(depth) .. string.format("🎰 :%s", slot.name or "unknown")

      -- Add slot details (required, attributes count)
      local details = {}
      if slot.required then table.insert(details, "required") end
      if slot.attributes and #slot.attributes > 0 then
        table.insert(details, #slot.attributes .. " attrs")
      end
      if #details > 0 then
        slot_line = slot_line .. " (" .. table.concat(details, ", ") .. ")"
      end

      add_line(slot_line, slot_id, depth, "component-slot", { component = component, slot = slot }, parent_id, false)
    end
  end
end

-- Group LiveViews by folder path
local function group_liveviews_by_folder(liveviews)
  local folder_map = {}

  for _, module in ipairs(liveviews) do
    -- Parse module name: MyAppWeb.UserLive.IndexLive → extract "UserLive"
    local parts = {}
    for part in string.gmatch(module.module or "", "[^%.]+") do
      table.insert(parts, part)
    end

    -- Extract folder path (between Web module and file name)
    local folder_path = "root"
    if #parts > 2 then
      -- Remove first part (Web module) and last part (file name)
      folder_path = parts[#parts - 1]
    elseif #parts == 2 then
      folder_path = parts[1]
    end

    if not folder_map[folder_path] then
      folder_map[folder_path] = {}
    end
    table.insert(folder_map[folder_path], module)
  end

  -- Convert to sorted array
  local folders = {}
  for folder_path, modules in pairs(folder_map) do
    table.insert(folders, { path = folder_path, modules = modules })
  end
  table.sort(folders, function(a, b) return a.path < b.path end)

  return folders
end

-- Get icon for LiveView function type
local function get_liveview_function_icon(func_type)
  if func_type == "mount" or func_type == "handle_params" then
    return "🔵"  -- Blue for lifecycle
  elseif func_type == "handle_event" then
    return "⚡"  -- Yellow for events
  elseif func_type == "handle_info" then
    return "🔔"  -- Purple for info
  elseif func_type == "render" then
    return "📝"  -- Green for render
  else
    return "📌"  -- Default
  end
end

-- Render LiveView module children (functions)
local function render_liveview_module_children(module, parent_id, depth)
  if not is_expanded(parent_id) then
    return
  end

  if module.functions and #module.functions > 0 then
    for _, func in ipairs(module.functions) do
      local func_id = generate_liveview_func_id(module, func)
      local func_icon = get_liveview_function_icon(func.type)
      local func_name = func.name or "unknown"

      -- Add event name for handle_event
      if func.type == "handle_event" and func.eventName then
        func_name = func_name .. " \"" .. func.eventName .. "\""
      end

      local func_line = get_indentation(depth) .. string.format("%s %s", func_icon, func_name)
      add_line(func_line, func_id, depth, "liveview-function", { module = module, func = func }, parent_id, false)
    end
  end
end

-- Render LiveView folder children (modules)
local function render_liveview_folder_children(folder, parent_id, depth)
  if not is_expanded(parent_id) then
    return
  end

  for _, module in ipairs(folder.modules) do
    local module_id = generate_liveview_module_id(module)

    -- Extract module file name (last part of module name)
    local parts = {}
    for part in string.gmatch(module.module or "", "[^%.]+") do
      table.insert(parts, part)
    end
    local file_name = parts[#parts] or "Unknown"

    local has_children = module.functions and #module.functions > 0
    local expanded_icon = has_children and (is_expanded(module_id) and "▼" or "▶") or ""
    local prefix = has_children and (expanded_icon .. " ") or ""

    local line = get_indentation(depth) .. prefix .. string.format("📄 %s", file_name)
    if has_children then
      line = line .. string.format(" (%d functions)", #module.functions)
    end

    add_line(line, module_id, depth, "liveview-module", module, parent_id, has_children)

    -- Render module children if expanded
    if has_children then
      render_liveview_module_children(module, module_id, depth + 1)
    end
  end
end

-- Compute project statistics
local function compute_statistics()
  local schemas = M.state.data.schemas or {}
  local components = M.state.data.components or {}
  local routes = M.state.data.routes or {}
  local events = M.state.data.events or {}
  local liveviews = M.state.data.liveviews or {}

  -- Count top schemas by field + association count
  local schemas_with_counts = {}
  for _, schema in ipairs(schemas) do
    local field_count = schema.fields and #schema.fields or 0
    local assoc_count = schema.associations and #schema.associations or 0
    table.insert(schemas_with_counts, {
      schema = schema,
      total_count = field_count + assoc_count
    })
  end
  table.sort(schemas_with_counts, function(a, b) return a.total_count > b.total_count end)

  -- Get top 3
  local top_schemas = {}
  for i = 1, math.min(3, #schemas_with_counts) do
    table.insert(top_schemas, schemas_with_counts[i])
  end

  return {
    total_schemas = #schemas,
    total_components = #components,
    total_routes = #routes,
    total_events = #events,
    total_liveviews = #liveviews,
    top_schemas = top_schemas
  }
end

-- Render statistics section (always expanded)
local function render_statistics()
  local stats = compute_statistics()

  -- Title
  add_line("📊 Project Statistics", nil, 0, "statistics-title", nil, nil, false)

  -- Totals
  local totals_line = get_indentation(1) .. string.format(
    "📈 %d Schemas, %d Components, %d Routes, %d Events, %d LiveViews",
    stats.total_schemas,
    stats.total_components,
    stats.total_routes,
    stats.total_events,
    stats.total_liveviews
  )
  add_line(totals_line, nil, 1, "statistics-totals", nil, nil, false)

  -- Top schemas (if any)
  if #stats.top_schemas > 0 then
    add_line(get_indentation(1) .. "🏆 Top Schemas:", nil, 1, "statistics-top-label", nil, nil, false)
    for _, entry in ipairs(stats.top_schemas) do
      local schema_name = entry.schema.name or "Unknown"
      local count = entry.total_count
      local line = get_indentation(2) .. string.format("%s (%d fields)", schema_name, count)
      add_line(line, nil, 2, "statistics-top-schema", entry.schema, nil, false)
    end
  end

  add_line("", nil, 0, "empty", nil, nil, false)
end

--============================================================================
-- Search/Filter Functionality
-- ============================================================================

-- Check if item matches search query
local function matches_search(item)
  if M.state.search_query == "" then
    return true
  end

  local query = M.state.search_query:lower()

  -- Check various fields
  if item.name and string.find(item.name:lower(), query, 1, true) then
    return true
  end
  if item.module and string.find(item.module:lower(), query, 1, true) then
    return true
  end
  if item.filePath and string.find(item.filePath:lower(), query, 1, true) then
    return true
  end
  if item.file and string.find(item.file:lower(), query, 1, true) then
    return true
  end
  if item.path and string.find(item.path:lower(), query, 1, true) then
    return true
  end

  return false
end

-- Open search prompt
local function search()
  vim.ui.input({ prompt = "Search: ", default = M.state.search_query }, function(input)
    if input ~= nil then  -- nil means cancelled
      M.state.search_query = input
      M.render()
    end
  end)
end

-- Clear search filter
local function clear_search()
  M.state.search_query = ""
  M.render()
end

-- ============================================================================
-- End of Search/Filter Functionality
-- ============================================================================

-- ============================================================================
-- Copy Commands (Context-Aware Clipboard Operations)
-- ============================================================================

-- Copy text to clipboard and show notification
local function copy_to_clipboard(text, description)
  vim.fn.setreg('+', text)
  vim.notify(string.format("[Phoenix Pulse] Copied %s: %s", description, text), vim.log.levels.INFO)
end

-- Open copy menu based on current line's item
local function copy_menu()
  local line = vim.api.nvim_win_get_cursor(M.state.win)[1]
  local map_entry = M.state.line_map[line]

  if not map_entry or not map_entry.item then
    vim.notify("[Phoenix Pulse] No item to copy", vim.log.levels.WARN)
    return
  end

  local item = map_entry.item
  local item_type = map_entry.type
  local options = {}

  -- Build context-aware options based on item type
  if item_type == "schema" or (item_type == "schema-field" and item.schema) or (item_type == "schema-association" and item.schema) then
    local schema = item.schema or item

    table.insert(options, {
      label = "Copy Name",
      action = function()
        copy_to_clipboard(schema.name or "Unknown", "schema name")
      end
    })

    table.insert(options, {
      label = "Copy Module Name",
      action = function()
        copy_to_clipboard(schema.module or "Unknown", "module name")
      end
    })

    if schema.table then
      table.insert(options, {
        label = "Copy Table Name",
        action = function()
          copy_to_clipboard(schema.table, "table name")
        end
      })
    end

    if schema.filePath or schema.file then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(schema.filePath or schema.file, "file path")
        end
      })
    end

  elseif item_type == "component" or (item_type == "component-attribute" and item.component) or (item_type == "component-slot" and item.component) then
    local component = item.component or item

    table.insert(options, {
      label = "Copy Name",
      action = function()
        copy_to_clipboard(component.name or "Unknown", "component name")
      end
    })

    table.insert(options, {
      label = "Copy Module Name",
      action = function()
        copy_to_clipboard(component.module or "Unknown", "module name")
      end
    })

    table.insert(options, {
      label = "Copy Tag",
      action = function()
        local tag = "<." .. (component.name or "unknown") .. " />"
        copy_to_clipboard(tag, "component tag")
      end
    })

    if component.filePath or component.file then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(component.filePath or component.file, "file path")
        end
      })
    end

  elseif item_type == "route" then
    table.insert(options, {
      label = "Copy Path",
      action = function()
        copy_to_clipboard(item.path or "/", "route path")
      end
    })

    table.insert(options, {
      label = "Copy Full Route",
      action = function()
        local method = item.verb or item.method or "GET"
        local path = item.path or "/"
        local full = method .. " " .. path
        copy_to_clipboard(full, "full route")
      end
    })

    if item.file or item.filePath then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(item.file or item.filePath, "file path")
        end
      })
    end

  elseif item_type == "event" then
    table.insert(options, {
      label = "Copy Name",
      action = function()
        copy_to_clipboard(item.name or "Unknown", "event name")
      end
    })

    if item.filePath or item.file then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(item.filePath or item.file, "file path")
        end
      })
    end

  elseif item_type == "liveview-function" and item.module then
    local func = item.func or {}

    table.insert(options, {
      label = "Copy Function Name",
      action = function()
        copy_to_clipboard(func.name or "Unknown", "function name")
      end
    })

    if func.eventName then
      table.insert(options, {
        label = "Copy Event Name",
        action = function()
          copy_to_clipboard(func.eventName, "event name")
        end
      })
    end

    if item.module.filePath or item.module.file then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(item.module.filePath or item.module.file, "file path")
        end
      })
    end

  elseif item_type == "liveview-module" then
    table.insert(options, {
      label = "Copy Module Name",
      action = function()
        copy_to_clipboard(item.module or "Unknown", "module name")
      end
    })

    if item.filePath or item.file then
      table.insert(options, {
        label = "Copy File Path",
        action = function()
          copy_to_clipboard(item.filePath or item.file, "file path")
        end
      })
    end

  elseif item_type == "liveview-folder" then
    table.insert(options, {
      label = "Copy Folder Name",
      action = function()
        copy_to_clipboard(item.path or "Unknown", "folder name")
      end
    })
  end

  -- Show menu if we have options
  if #options == 0 then
    vim.notify("[Phoenix Pulse] No copy options available for this item", vim.log.levels.WARN)
    return
  end

  -- Build labels for vim.ui.select
  local labels = {}
  for _, opt in ipairs(options) do
    table.insert(labels, opt.label)
  end

  vim.ui.select(labels, {
    prompt = "Copy:",
  }, function(choice, idx)
    if choice and idx then
      options[idx].action()
    end
  end)
end

-- ============================================================================
-- End of Copy Commands
-- ============================================================================

-- ============================================================================
-- End of Hierarchical Rendering Engine
-- ============================================================================

-- Toggle category expansion
local function toggle_category(category)
  M.state.expanded[category] = not M.state.expanded[category]
  M.render()
end

-- Jump to definition
local function jump_to_definition(item)
  -- Handle schema field/association - jump to parent schema
  if item.schema then
    item = item.schema
  end

  -- Handle component attribute/slot - jump to parent component
  if item.component then
    item = item.component
  end

  -- Handle LiveView function - jump to parent module
  if item.module then
    item = item.module
  end

  -- Map LSP response fields to what we need
  local file = item.filePath or item.file
  local line = nil

  -- For LiveView functions, check func.location
  if item.func and item.func.location then
    line = item.func.location.line + 1
  elseif item.location and item.location.line then
    line = item.location.line + 1  -- LSP returns 0-based, Neovim uses 1-based
  elseif item.line then
    line = item.line
  end

  if not file then
    vim.notify("[Phoenix Pulse] No file information available", vim.log.levels.WARN)
    return
  end

  -- Keep explorer open - user can close it manually with q/<Esc>
  -- Open file
  vim.cmd("edit " .. file)

  -- Jump to line if available
  if line and line > 0 then
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    -- Center the line in the window
    vim.cmd("normal! zz")
  end
end

-- Handle mouse click on a line
local function handle_click()
  local line = vim.api.nvim_win_get_cursor(M.state.win)[1]
  local map_entry = M.state.line_map[line]

  if not map_entry then
    return
  end

  -- Handle category toggle (old behavior)
  if map_entry.type == "category" then
    toggle_category(map_entry.name)
    return
  end

  -- Handle hierarchical items with children (expansion toggle)
  if map_entry.has_children and map_entry.id then
    toggle_expansion(map_entry.id)
    return
  end

  -- Handle items without children (navigate to definition)
  if map_entry.item then
    jump_to_definition(map_entry.item)
  end
end

-- Setup syntax highlighting
local function setup_syntax_highlighting(buf)
  -- Define highlight groups
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax clear

      " Title
      syntax match PhoenixPulseTitle /^📦.*$/
      highlight link PhoenixPulseTitle Title

      " Category headers (lines with ▶ or ▼)
      syntax match PhoenixPulseCategory /^[▶▼].*$/
      highlight link PhoenixPulseCategory Statement

      " Item lines (indented with icons)
      syntax match PhoenixPulseItem /^  .*$/
      highlight link PhoenixPulseItem Normal

      " Icons
      syntax match PhoenixPulseIcon /[📊🧩🛣️⚡📄🧱➡️🔔]/
      highlight link PhoenixPulseIcon Special

      " HTTP methods
      syntax match PhoenixPulseMethod /\<\(GET\|POST\|PUT\|PATCH\|DELETE\)\>/
      highlight PhoenixPulseGET ctermfg=Green guifg=#10b981
      highlight PhoenixPulsePOST ctermfg=Blue guifg=#3b82f6
      highlight PhoenixPulsePUT ctermfg=Yellow guifg=#f59e0b
      highlight PhoenixPulsePATCH ctermfg=Cyan guifg=#06b6d4
      highlight PhoenixPulseDELETE ctermfg=Red guifg=#ef4444

      " Paths
      syntax match PhoenixPulsePath /\/[^ ]*/ contained
      highlight link PhoenixPulsePath String
    ]])
  end)
end

-- Render the explorer tree
function M.render()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end

  -- Initialize render state
  render_state = {
    current_line = 1,
    lines = {},
    line_map = {}
  }

  -- Title with search indicator
  local title = "📦 Phoenix Pulse Explorer"
  if M.state.search_query ~= "" then
    title = title .. " [Search: " .. M.state.search_query .. "]"
  end
  add_line(title, nil, 0, "title", nil, nil, false)
  add_line("", nil, 0, "empty", nil, nil, false)
  add_line("  💡 <CR>: open | r: refresh | /: search | x: clear | y: copy | ?: help", nil, 0, "help", nil, nil, false)
  add_line("", nil, 0, "empty", nil, nil, false)

  -- Render statistics section (always expanded)
  render_statistics()

  -- Render categories (keeping backward compatibility for now)
  -- Phase 3-6 will add hierarchical children

  -- Helper to add category (temporary, will be replaced in Phase 3+)
  local function add_category(name, display_name, items, item_type, render_fn)
    local icon = get_icon(name)
    local expanded_icon = M.state.expanded[name] and "▼" or "▶"

    -- Filter items based on search query
    local filtered_items = {}
    if items then
      for _, item in ipairs(items) do
        if matches_search(item) then
          table.insert(filtered_items, item)
        end
      end
    end

    local count = #filtered_items

    local header = string.format("%s %s %s (%d)", expanded_icon, icon, display_name, count)
    local category_id = generate_category_id(name)
    add_line(header, category_id, 0, "category", { name = name }, nil, false)

    if M.state.expanded[name] and #filtered_items > 0 then
      for _, item in ipairs(filtered_items) do
        local line = get_indentation(1) .. render_fn(item)
        local item_id = nil

        -- Generate appropriate ID based on item type
        if item_type == "schema" then
          item_id = generate_schema_id(item)
        elseif item_type == "component" then
          item_id = generate_component_id(item)
        elseif item_type == "route" then
          item_id = generate_route_id(item)
        elseif item_type == "event" then
          item_id = generate_event_id(item)
        elseif item_type == "template" then
          item_id = generate_template_id(item)
        elseif item_type == "controller" then
          item_id = generate_controller_id(item)
        elseif item_type == "asset" then
          item_id = generate_asset_id(item)
        end

        -- Determine if item has children (Phase 3+ will implement this)
        local has_children = false

        add_line(line, item_id, 1, item_type, item, category_id, has_children)
      end
    end

    add_line("", nil, 0, "empty", nil, nil, false)
  end

  -- Render all categories

  -- Schemas category (special handling for hierarchical details)
  do
    local name = "schemas"
    local icon = get_icon(name)
    local expanded_icon = M.state.expanded[name] and "▼" or "▶"
    local items = M.state.data.schemas

    -- Filter items based on search query
    local filtered_items = {}
    if items then
      for _, schema in ipairs(items) do
        if matches_search(schema) then
          table.insert(filtered_items, schema)
        end
      end
    end

    local count = #filtered_items

    local header = string.format("%s %s Schemas (%d)", expanded_icon, icon, count)
    local category_id = generate_category_id(name)
    add_line(header, category_id, 0, "category", { name = name }, nil, false)

    if M.state.expanded[name] and #filtered_items > 0 then
      for _, schema in ipairs(filtered_items) do
        local schema_id = generate_schema_id(schema)

        -- Determine if schema has children (fields or associations)
        local has_children = (schema.fields and #schema.fields > 0) or (schema.associations and #schema.associations > 0)

        -- Add expand/collapse icon if has children
        local expanded_icon = has_children and (is_expanded(schema_id) and "▼" or "▶") or ""
        local prefix = has_children and (expanded_icon .. " ") or ""

        local line = get_indentation(1) .. prefix .. string.format("%s %s", get_icon("schema"), schema.name or "Unknown")
        add_line(line, schema_id, 1, "schema", schema, category_id, has_children)

        -- Render schema children if expanded
        if has_children then
          render_schema_children(schema, schema_id, 2)
        end
      end
    end

    add_line("", nil, 0, "empty", nil, nil, false)
  end

  -- Components category (special handling for hierarchical details)
  do
    local name = "components"
    local icon = get_icon(name)
    local expanded_icon = M.state.expanded[name] and "▼" or "▶"
    local items = M.state.data.components

    -- Filter items based on search query
    local filtered_items = {}
    if items then
      for _, component in ipairs(items) do
        if matches_search(component) then
          table.insert(filtered_items, component)
        end
      end
    end

    local count = #filtered_items

    local header = string.format("%s %s Components (%d)", expanded_icon, icon, count)
    local category_id = generate_category_id(name)
    add_line(header, category_id, 0, "category", { name = name }, nil, false)

    if M.state.expanded[name] and #filtered_items > 0 then
      for _, component in ipairs(filtered_items) do
        local component_id = generate_component_id(component)

        -- Determine if component has children (attributes or slots)
        local has_children = (component.attributes and #component.attributes > 0) or (component.slots and #component.slots > 0)

        -- Add expand/collapse icon if has children
        local expanded_icon = has_children and (is_expanded(component_id) and "▼" or "▶") or ""
        local prefix = has_children and (expanded_icon .. " ") or ""

        local line = get_indentation(1) .. prefix .. string.format("%s %s", get_icon("component"), component.name or "Unknown")
        add_line(line, component_id, 1, "component", component, category_id, has_children)

        -- Render component children if expanded
        if has_children then
          render_component_children(component, component_id, 2)
        end
      end
    end

    add_line("", nil, 0, "empty", nil, nil, false)
  end

  add_category("routes", "Routes", M.state.data.routes, "route", function(route)
    local method = route.verb or route.method or "GET"
    local path = route.path or "/"
    return string.format("%s %s %s", get_icon("route"), method, path)
  end)

  add_category("events", "Events", M.state.data.events, "event", function(event)
    return string.format("%s %s", get_icon("event"), event.name or "Unknown")
  end)

  -- LiveViews category (3-level hierarchy: folders → modules → functions)
  do
    local name = "liveviews"
    local icon = "🔴"  -- Red circle for LiveViews
    local expanded_icon = M.state.expanded[name] and "▼" or "▶"
    local items = M.state.data.liveviews

    -- Filter items based on search query
    local filtered_items = {}
    if items then
      for _, module in ipairs(items) do
        if matches_search(module) then
          table.insert(filtered_items, module)
        end
      end
    end

    local total_modules = #filtered_items

    local header = string.format("%s %s LiveViews (%d)", expanded_icon, icon, total_modules)
    local category_id = generate_category_id(name)
    add_line(header, category_id, 0, "category", { name = name }, nil, false)

    if M.state.expanded[name] and #filtered_items > 0 then
      -- Group LiveViews by folder
      local folders = group_liveviews_by_folder(filtered_items)

      for _, folder in ipairs(folders) do
        local folder_id = generate_liveview_folder_id(folder.path)
        local has_children = #folder.modules > 0

        local folder_expanded_icon = has_children and (is_expanded(folder_id) and "▼" or "▶") or ""
        local prefix = has_children and (folder_expanded_icon .. " ") or ""

        local line = get_indentation(1) .. prefix .. string.format("📁 %s (%d modules)", folder.path, #folder.modules)
        add_line(line, folder_id, 1, "liveview-folder", folder, category_id, has_children)

        -- Render folder children if expanded
        if has_children then
          render_liveview_folder_children(folder, folder_id, 2)
        end
      end
    end

    add_line("", nil, 0, "empty", nil, nil, false)
  end

  -- Update buffer
  ui.render_lines(M.state.buf, render_state.lines)
  M.state.lines = render_state.lines
  M.state.line_map = render_state.line_map

  -- Apply syntax highlighting
  setup_syntax_highlighting(M.state.buf)
end

-- Refresh data from LSP
function M.refresh()
  vim.notify("[Phoenix Pulse] Refreshing...", vim.log.levels.INFO)

  -- Fetch schemas
  lsp.call_lsp_command("phoenix/listSchemas", {}, function(result)
    M.state.data.schemas = result or {}
    M.render()
  end)

  -- Fetch components
  lsp.call_lsp_command("phoenix/listComponents", {}, function(result)
    M.state.data.components = result or {}
    M.render()
  end)

  -- Fetch routes
  lsp.call_lsp_command("phoenix/listRoutes", {}, function(result)
    M.state.data.routes = result or {}
    M.render()
  end)

  -- Fetch events
  lsp.call_lsp_command("phoenix/listEvents", {}, function(result)
    M.state.data.events = result or {}
    M.render()
  end)

  -- Fetch LiveViews
  lsp.call_lsp_command("phoenix/listLiveView", {}, function(result)
    M.state.data.liveviews = result or {}
    M.render()
  end)
end

-- Open explorer with specified mode
function M.open(mode)
  mode = mode or "float"
  M.state.mode = mode

  -- Create window
  local win_state
  if mode == "float" then
    win_state = ui.create_float_window("Phoenix Pulse Explorer", 0.7, 0.8)
  else
    win_state = ui.create_split_window("Phoenix Pulse Explorer", 45)
  end

  M.state.win = win_state.win
  M.state.buf = win_state.buf

  -- Enable mouse support in window
  vim.api.nvim_win_set_option(M.state.win, "mouse", "a")

  -- Setup keybindings
  ui.setup_buffer_keymaps(M.state.buf, {
    -- Close
    ["q"] = function() M.close() end,
    ["<Esc>"] = function() M.close() end,

    -- Expand/collapse or open with Enter/Space
    ["<CR>"] = function() handle_click() end,
    ["<Space>"] = function() handle_click() end,

    -- Mouse support
    ["<LeftMouse>"] = function() handle_click() end,
    ["<2-LeftMouse>"] = function() handle_click() end,  -- Double-click

    -- Refresh
    ["r"] = function() M.refresh() end,
    ["<F5>"] = function() M.refresh() end,
    ["R"] = function() M.refresh() end,

    -- Search
    ["/"] = function() search() end,
    ["x"] = function() clear_search() end,

    -- Copy
    ["y"] = function() copy_menu() end,

    -- Navigation
    ["j"] = function() vim.cmd("normal! j") end,
    ["k"] = function() vim.cmd("normal! k") end,
    ["<Down>"] = function() vim.cmd("normal! j") end,
    ["<Up>"] = function() vim.cmd("normal! k") end,
    ["<C-d>"] = function() vim.cmd("normal! \\<C-d>") end,
    ["<C-u>"] = function() vim.cmd("normal! \\<C-u>") end,
    ["gg"] = function() vim.cmd("normal! gg") end,
    ["G"] = function() vim.cmd("normal! G") end,

    -- Expand/collapse all
    ["za"] = function() handle_click() end,  -- Toggle current
    ["zM"] = function()  -- Collapse all
      for key, _ in pairs(M.state.expanded) do
        M.state.expanded[key] = false
      end
      M.render()
    end,
    ["zR"] = function()  -- Expand all
      for key, _ in pairs(M.state.expanded) do
        M.state.expanded[key] = true
      end
      M.render()
    end,

    -- Search
    ["/"] = function() search() end,
    ["x"] = function() clear_search() end,

    -- Copy
    ["y"] = function() copy_menu() end,

    -- Help
    ["?"] = function()
      vim.notify([[
Phoenix Pulse Explorer Keys:
  <CR>/Space/Click - Open file or toggle category
  j/k or ↑/↓      - Navigate up/down
  <C-d>/<C-u>     - Page down/up
  gg/G            - Jump to top/bottom
  za              - Toggle current category
  zM              - Collapse all categories
  zR              - Expand all categories
  /               - Search/filter items
  x               - Clear search filter
  y               - Copy menu (context-aware)
  r/<F5>          - Refresh data
  q/<Esc>         - Close explorer
  ?               - Show this help
      ]], vim.log.levels.INFO)
    end,
  })

  -- Set cursor style to indicate clickable
  vim.api.nvim_win_set_option(M.state.win, "cursorline", true)

  -- Initial render
  M.render()

  -- Fetch data
  M.refresh()
end

-- Close explorer
function M.close()
  ui.close_window(M.state.win)
  M.state.win = nil
  M.state.buf = nil
end

-- Toggle explorer
function M.toggle()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    M.close()
  else
    M.open(M.state.mode)
  end
end

return M
