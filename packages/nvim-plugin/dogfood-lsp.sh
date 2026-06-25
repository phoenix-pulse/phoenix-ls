#!/bin/bash
# Phoenix Pulse Neovim LSP dogfood runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-lsp.sh"
SERVER="$SCRIPT_DIR/server/phoenix_ls"
FIXTURE_SOURCE="${PHOENIX_PULSE_FIXTURE_ROOT:-$PROJECT_ROOT/server/apps/phoenix_ls/test/fixtures/liveview_components_app}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/phoenix-pulse-nvim-dogfood.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

fail() {
  echo "Error: $*" >&2
  exit 1
}

find_lspconfig_root() {
  if [ -n "${NVIM_LSPCONFIG_ROOT:-}" ]; then
    if [ -f "$NVIM_LSPCONFIG_ROOT/lua/lspconfig.lua" ]; then
      echo "$NVIM_LSPCONFIG_ROOT"
      return 0
    fi

    fail "NVIM_LSPCONFIG_ROOT does not look like nvim-lspconfig: $NVIM_LSPCONFIG_ROOT"
  fi

  local candidate="$HOME/.local/share/nvim/lazy/nvim-lspconfig"
  if [ -f "$candidate/lua/lspconfig.lua" ]; then
    echo "$candidate"
    return 0
  fi

  candidate="$(find "$HOME/.local/share/nvim" -maxdepth 5 -type f -path '*/nvim-lspconfig/lua/lspconfig.lua' -print 2>/dev/null | head -1 || true)"
  if [ -n "$candidate" ]; then
    dirname "$(dirname "$candidate")"
    return 0
  fi

  fail "nvim-lspconfig not found. Set NVIM_LSPCONFIG_ROOT=/path/to/nvim-lspconfig."
}

first_elixir_file() {
  local root="$1"
  local live_file

  live_file="$(find "$root" -type f -path '*_live.ex' -print | sort | head -1 || true)"
  if [ -n "$live_file" ]; then
    echo "$live_file"
    return 0
  fi

  find "$root" -type f -name '*.ex' -print | sort | head -1
}

write_dogfood_lua() {
  local target="$1"

  cat > "$target" <<'LUA'
local methods = {
  "phoenix/listSchemas",
  "phoenix/listComponents",
  "phoenix/listRoutes",
  "phoenix/listTemplates",
  "phoenix/listEvents",
  "phoenix/listLiveView",
}

local server_path = vim.env.PHOENIX_PULSE_SERVER_PATH
local page_file = vim.env.PHOENIX_PULSE_PAGE_FILE

if not server_path or server_path == "" then
  error("PHOENIX_PULSE_SERVER_PATH is required")
end

if not page_file or page_file == "" then
  error("PHOENIX_PULSE_PAGE_FILE is required")
end

require("phoenix-pulse").setup({
  lsp_server_path = server_path,
  keybindings = false,
  log_level = "error",
  source_only_mode = true,
  indexing_enabled = true,
  compilation_enabled = false,
})

vim.cmd("edit " .. vim.fn.fnameescape(page_file))
vim.cmd("set filetype=elixir")

local function phoenix_clients()
  if vim.lsp.get_clients then
    return vim.lsp.get_clients({ name = "phoenix_pulse" })
  end

  return vim.lsp.get_active_clients({ name = "phoenix_pulse" })
end

local attached = vim.wait(10000, function()
  return #phoenix_clients() > 0
end, 50)

if not attached then
  error("phoenix_pulse LSP client did not start")
end

local lsp = require("phoenix-pulse.lsp")
local results = {}
local pending = #methods

for _, method in ipairs(methods) do
  lsp.call_lsp_command(method, {}, function(result)
    results[method] = result
    pending = pending - 1
  end)
end

local completed = vim.wait(10000, function()
  return pending == 0
end, 50)

if not completed then
  error("timed out waiting for phoenix/list* responses")
end

local counts = {}
local missing = {}

for _, method in ipairs(methods) do
  local result = results[method]
  local count = type(result) == "table" and #result or -1
  counts[method] = count

  if count <= 0 then
    table.insert(missing, method)
  end
end

if #missing > 0 then
  error("missing non-empty results: " .. table.concat(missing, ", ") .. " counts=" .. vim.inspect(counts))
end

local summary = vim.json.encode({ client_id = phoenix_clients()[1].id, counts = counts })
local counts_file = vim.env.PHOENIX_PULSE_COUNTS_FILE

if counts_file and counts_file ~= "" then
  vim.fn.writefile({ summary }, counts_file)
end

print(summary)
vim.cmd("qa!")
LUA
}

command -v nvim >/dev/null 2>&1 || fail "nvim is not installed"

if [ ! -d "$FIXTURE_SOURCE" ]; then
  fail "Phoenix fixture not found: $FIXTURE_SOURCE"
fi

"$INSTALLER" >/dev/null

if [ ! -x "$SERVER" ]; then
  fail "Phoenix LS executable not found after install: $SERVER"
fi

LSPCONFIG_ROOT="$(find_lspconfig_root)"
APP_ROOT="$TMP_ROOT/liveview_components_app"
LUA_SCRIPT="$TMP_ROOT/nvim-dogfood.lua"
NVIM_OUT="$TMP_ROOT/nvim.out"
NVIM_ERR="$TMP_ROOT/nvim.err"
COUNTS_FILE="$TMP_ROOT/counts.json"

cp -R "$FIXTURE_SOURCE" "$APP_ROOT"
PAGE_FILE="$(first_elixir_file "$APP_ROOT")"

if [ -z "$PAGE_FILE" ]; then
  fail "no Elixir file found in copied fixture: $APP_ROOT"
fi

write_dogfood_lua "$LUA_SCRIPT"

if ! PHOENIX_PULSE_SERVER_PATH="$SERVER" \
  PHOENIX_PULSE_PAGE_FILE="$PAGE_FILE" \
  PHOENIX_PULSE_COUNTS_FILE="$COUNTS_FILE" \
  nvim --headless -u NONE -n \
    --cmd "set runtimepath^=$LSPCONFIG_ROOT" \
    --cmd "set runtimepath^=$SCRIPT_DIR" \
    "$APP_ROOT/mix.exs" \
    +"luafile $LUA_SCRIPT" >"$NVIM_OUT" 2>"$NVIM_ERR"; then
  echo "--- nvim stdout ---" >&2
  cat "$NVIM_OUT" >&2
  echo "--- nvim stderr ---" >&2
  cat "$NVIM_ERR" >&2
  fail "Neovim dogfood failed"
fi

if grep -i "deprecated" "$NVIM_OUT" "$NVIM_ERR" >/dev/null 2>&1; then
  echo "--- nvim stdout ---" >&2
  cat "$NVIM_OUT" >&2
  echo "--- nvim stderr ---" >&2
  cat "$NVIM_ERR" >&2
  fail "Neovim dogfood emitted deprecated API warnings"
fi

if [ ! -s "$COUNTS_FILE" ]; then
  echo "--- nvim stdout ---" >&2
  cat "$NVIM_OUT" >&2
  echo "--- nvim stderr ---" >&2
  cat "$NVIM_ERR" >&2
  fail "Neovim dogfood did not write request counts"
fi

cat "$COUNTS_FILE"
echo "Neovim dogfood passed"
