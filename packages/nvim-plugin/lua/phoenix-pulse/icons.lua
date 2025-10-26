-- Phoenix Pulse Icon Mappings
-- Integrates with nvim-web-devicons if available, falls back to text

local M = {}

-- Check if nvim-web-devicons is available
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- Icon mappings (emoji fallback)
local icon_map = {
  schemas = "📊",
  schema = "📄",
  components = "🧩",
  component = "🧱",
  routes = "🛣️",
  route = "➡️",
  events = "⚡",
  event = "🔔",
  templates = "🎨",
  template = "📝",
  controllers = "🎮",
  controller = "🎛️",
  assets = "🖼️",
  asset = "📦",
}

-- Text fallback (no emoji support)
local text_fallback = {
  schemas = "[S]",
  schema = "[s]",
  components = "[C]",
  component = "[c]",
  routes = "[R]",
  route = "[r]",
  events = "[E]",
  event = "[e]",
  templates = "[T]",
  template = "[t]",
  controllers = "[K]",
  controller = "[k]",
  assets = "[A]",
  asset = "[a]",
}

-- Detect if terminal supports emoji
local function supports_emoji()
  -- Check if terminal supports UTF-8
  if vim.o.encoding ~= "utf-8" then
    return false
  end

  -- Check if TERM supports emoji (heuristic)
  local term = vim.env.TERM or ""
  return term:match("xterm") or term:match("kitty") or term:match("alacritty")
end

-- Get icon for a category/type
function M.get_icon(name)
  -- Try nvim-web-devicons first
  if has_devicons then
    local icon = devicons.get_icon(name, nil, { default = false })
    if icon then
      return icon
    end
  end

  -- Fall back to emoji or text
  if supports_emoji() then
    return icon_map[name] or "•"
  else
    return text_fallback[name] or "[?]"
  end
end

return M
