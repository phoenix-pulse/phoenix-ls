-- Phoenix Pulse UI Utilities
-- Shared functions for creating windows and rendering content

local M = {}

-- Create a centered floating window
function M.create_float_window(title, width_percent, height_percent)
  width_percent = width_percent or 0.8
  height_percent = height_percent or 0.8

  local width = math.floor(vim.o.columns * width_percent)
  local height = math.floor(vim.o.lines * height_percent)

  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)  -- No file, scratch buffer
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "phoenix-pulse")

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = title or "Phoenix Pulse",
    title_pos = "center",
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Window settings
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)

  return { buf = buf, win = win }
end

-- Create a split window (sidebar)
function M.create_split_window(title, width)
  width = width or 40

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "phoenix-pulse")

  -- Create vertical split
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()

  -- Set buffer in window
  vim.api.nvim_win_set_buf(win, buf)

  -- Resize window
  vim.api.nvim_win_set_width(win, width)

  -- Window settings
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)

  return { buf = buf, win = win }
end

-- Render lines with syntax highlighting
function M.render_lines(buf, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Setup keybindings for a buffer
function M.setup_buffer_keymaps(buf, keymaps)
  for key, action in pairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
      noremap = true,
      silent = true,
      callback = action,
    })
  end
end

-- Close window
function M.close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
