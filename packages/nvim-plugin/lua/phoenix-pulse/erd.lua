-- Phoenix Pulse ERD Viewer
-- Generates Entity Relationship Diagram using Mermaid.js

local M = {}
local lsp = require("phoenix-pulse.lsp")

-- Generate Mermaid ERD syntax from schemas
local function generate_mermaid_code(schemas)
  if not schemas or #schemas == 0 then
    return "erDiagram\n    NO_SCHEMAS[\"No schemas found in project\"]"
  end

  local lines = { "erDiagram" }

  -- Helper: Get simple name from module path
  local function get_simple_name(module_path)
    local parts = vim.split(module_path, ".", { plain = true })
    return parts[#parts]
  end

  -- Helper: Get display name (table name or simple name)
  local function get_display_name(schema)
    return schema.tableName or get_simple_name(schema.name)
  end

  -- Build name mapping
  local name_map = {}
  for _, schema in ipairs(schemas) do
    name_map[schema.name] = get_display_name(schema)
  end

  -- Helper: Map association type to Mermaid symbol
  local function get_relationship_symbol(assoc_type)
    local map = {
      has_many = "||--o{",
      has_one = "||--||",
      belongs_to = "}o--||",
      many_to_many = "}o--o{",
      embeds_one = "||--||",
      embeds_many = "||--o{",
    }
    return map[assoc_type] or "||--||"
  end

  -- Generate relationships
  for _, schema in ipairs(schemas) do
    local source_name = get_display_name(schema)

    if schema.associations then
      for _, assoc in ipairs(schema.associations) do
        local target_name = name_map[assoc.targetModule] or get_simple_name(assoc.targetModule)
        local symbol = get_relationship_symbol(assoc.type)
        local label = (assoc.type or ""):gsub("_", " ")

        table.insert(lines, string.format("    %s %s %s : \"%s\"", source_name, symbol, target_name, label))
      end
    end
  end

  table.insert(lines, "")

  -- Generate schema definitions
  for _, schema in ipairs(schemas) do
    local display_name = get_display_name(schema)

    -- Add comment with Elixir module
    table.insert(lines, string.format("    %%%% %s", schema.name))

    -- Schema definition
    table.insert(lines, string.format("    %s {", display_name))

    -- Add fields (limit to 8)
    local fields = schema.fields or {}
    local fields_to_show = vim.list_slice(fields, 1, math.min(#fields, 8))

    for _, field in ipairs(fields_to_show) do
      local field_type = field.type or "string"
      local field_name = field.name or "unknown"
      local is_pk = field_name == "id"
      local is_fk = field_name:match("_id$")

      local constraint = ""
      if is_pk then
        constraint = " PK"
      elseif is_fk then
        constraint = " FK"
      end

      table.insert(lines, string.format("        %s %s%s", field_type, field_name, constraint))
    end

    -- Show count if more fields
    if #fields > 8 then
      table.insert(lines, string.format("        string plus_%d_more", #fields - 8))
    end

    table.insert(lines, "    }")
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Generate HTML with embedded Mermaid
local function generate_html(mermaid_code)
  local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Phoenix Schema Diagram</title>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <style>
        body {
            margin: 0;
            padding: 20px;
            background-color: #1e1e1e;
            color: #d4d4d4;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        #diagram {
            text-align: center;
            padding: 20px;
        }
        #info {
            position: fixed;
            bottom: 10px;
            left: 10px;
            background-color: #2d2d2d;
            padding: 10px;
            border-radius: 4px;
            font-size: 12px;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div id="diagram">
        <div class="mermaid">
]] .. mermaid_code .. [[

        </div>
    </div>
    <div id="info">
        💡 Table names shown | Elixir modules in comments | PK = Primary Key, FK = Foreign Key
    </div>
    <script>
        mermaid.initialize({
            startOnLoad: true,
            theme: 'dark',
            themeVariables: {
                primaryColor: '#3498db',
                primaryTextColor: '#fff',
                primaryBorderColor: '#2980b9',
                lineColor: '#7f8c8d',
                secondaryColor: '#2ecc71',
                tertiaryColor: '#e74c3c'
            },
            er: {
                diagramPadding: 30,
                layoutDirection: 'LR',
                minEntityWidth: 120,
                minEntityHeight: 80,
                entityPadding: 20,
                stroke: '#7f8c8d',
                fill: '#34495e',
                fontSize: 13
            }
        });
    </script>
</body>
</html>
]]
  return html
end

-- Open file in default browser
local function open_in_browser(filepath)
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    cmd = "start"
  else
    vim.notify("[Phoenix Pulse] Cannot detect OS to open browser", vim.log.levels.ERROR)
    return false
  end

  vim.fn.system(string.format("%s '%s'", cmd, filepath))
  return true
end

-- Show ERD diagram
function M.show()
  vim.notify("[Phoenix Pulse] Generating ERD diagram...", vim.log.levels.INFO)

  -- Fetch schemas from LSP
  lsp.call_lsp_command("phoenix/listSchemas", {}, function(schemas)
    if not schemas or #schemas == 0 then
      vim.notify("[Phoenix Pulse] No schemas found", vim.log.levels.WARN)
      return
    end

    -- Generate Mermaid code
    local mermaid_code = generate_mermaid_code(schemas)

    -- Generate HTML
    local html = generate_html(mermaid_code)

    -- Write to temp file
    local timestamp = os.time()
    local temp_file = string.format("/tmp/phoenix-pulse-erd-%d.html", timestamp)
    local file = io.open(temp_file, "w")

    if not file then
      vim.notify("[Phoenix Pulse] Failed to create temp file", vim.log.levels.ERROR)
      return
    end

    file:write(html)
    file:close()

    vim.notify("[Phoenix Pulse] ERD saved to: " .. temp_file, vim.log.levels.INFO)

    -- Open in browser
    if open_in_browser(temp_file) then
      vim.notify("[Phoenix Pulse] ERD opened in browser", vim.log.levels.INFO)
    end
  end)
end

-- Generate Mermaid file only
function M.generate_mermaid()
  vim.notify("[Phoenix Pulse] Generating Mermaid file...", vim.log.levels.INFO)

  lsp.call_lsp_command("phoenix/listSchemas", {}, function(schemas)
    if not schemas or #schemas == 0 then
      vim.notify("[Phoenix Pulse] No schemas found", vim.log.levels.WARN)
      return
    end

    -- Generate Mermaid code
    local mermaid_code = generate_mermaid_code(schemas)

    -- Write to file in current directory
    local output_file = "phoenix-erd.mmd"
    local file = io.open(output_file, "w")

    if not file then
      vim.notify("[Phoenix Pulse] Failed to create file", vim.log.levels.ERROR)
      return
    end

    file:write(mermaid_code)
    file:close()

    vim.notify("[Phoenix Pulse] Mermaid file saved to: " .. output_file, vim.log.levels.INFO)
  end)
end

return M
