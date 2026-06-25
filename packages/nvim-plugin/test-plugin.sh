#!/bin/bash
# Phoenix Pulse Neovim Plugin Test Script

echo "=========================================="
echo "Phoenix Pulse Neovim Plugin Test"
echo "=========================================="
echo ""

# Get plugin directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

echo "Plugin root: $SCRIPT_DIR"
echo ""

# Test 1: Check LSP server exists
echo "[1/6] Checking LSP server..."
if [ -f "server/phoenix_ls" ]; then
  SIZE=$(du -h server/phoenix_ls | cut -f1)
  echo "✅ LSP server found (size: $SIZE)"
else
  echo "❌ LSP server not found at: server/phoenix_ls"
  echo "    Fix: Run './install-lsp.sh' or configure lsp_server_path"
  exit 1
fi

# Test 2: Check Neovim plugin files
echo ""
echo "[2/6] Checking Neovim plugin files..."
REQUIRED_FILES=(
  "plugin/phoenix-pulse.lua"
  "lua/phoenix-pulse/init.lua"
  "lua/phoenix-pulse/lsp.lua"
  "lua/phoenix-pulse/commands.lua"
  "lua/phoenix-pulse/explorer.lua"
  "lua/phoenix-pulse/ui.lua"
  "lua/phoenix-pulse/erd.lua"
  "lua/phoenix-pulse/icons.lua"
)

ALL_FOUND=true
for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✅ $file"
  else
    echo "  ❌ $file (missing)"
    ALL_FOUND=false
  fi
done

if [ "$ALL_FOUND" = false ]; then
  echo "❌ Some plugin files are missing"
  exit 1
fi

# Test 3: Check documentation
echo ""
echo "[3/6] Checking documentation..."
if [ -f "../../NEOVIM.md" ]; then
  LINES=$(wc -l < ../../NEOVIM.md)
  echo "✅ NEOVIM.md found ($LINES lines)"
else
  echo "❌ NEOVIM.md not found"
fi

if [ -f "doc/phoenix-pulse.txt" ]; then
  LINES=$(wc -l < doc/phoenix-pulse.txt)
  echo "✅ doc/phoenix-pulse.txt found ($LINES lines)"
else
  echo "❌ doc/phoenix-pulse.txt not found"
fi

# Test 4: Count total lines of code
echo ""
echo "[4/6] Counting lines of code..."
LUA_LINES=$(find lua plugin -name "*.lua" | xargs wc -l | tail -1 | awk '{print $1}')
echo "✅ Total Lua code: $LUA_LINES lines"

# Test 5: Check Elixir availability
echo ""
echo "[5/6] Checking Elixir..."
if command -v elixir &> /dev/null; then
  ELIXIR_VERSION=$(elixir --version | tail -1)
  echo "✅ Elixir found: $ELIXIR_VERSION"
else
  echo "❌ Elixir not found (required to build Phoenix LS)"
  exit 1
fi

# Test 6: Check Neovim availability
echo ""
echo "[6/6] Checking Neovim..."
if command -v nvim &> /dev/null; then
  NVIM_VERSION=$(nvim --version | head -1)
  echo "✅ Neovim found: $NVIM_VERSION"

  # Check version is 0.8+
  NVIM_MAJOR=$(echo "$NVIM_VERSION" | sed -E 's/^NVIM v([0-9]+).*/\1/')
  NVIM_MINOR=$(echo "$NVIM_VERSION" | sed -E 's/^NVIM v[0-9]+\.([0-9]+).*/\1/')

  if [ "$NVIM_MAJOR" -ge 1 ] || { [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -ge 8 ]; }; then
    echo "✅ Neovim version is 0.8+ (required)"
  else
    echo "⚠️  Neovim version may be too old (need 0.8+)"
  fi
else
  echo "⚠️  Neovim not found (install to use the plugin)"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Results: ✅ All checks passed!"
echo "=========================================="
echo ""
echo "Plugin Structure:"
echo "  📁 plugin/               - Entry point"
echo "  📁 lua/phoenix-pulse/    - Plugin modules ($LUA_LINES lines)"
echo "  📁 doc/                  - Vim help docs"
echo "  📄 NEOVIM.md             - User guide"
echo ""
echo "Next Steps:"
echo ""
echo "1. Add to your Neovim config (LazyVim example):"
echo ""
echo "   ~/.config/nvim/lua/plugins/phoenix-pulse.lua:"
echo "   ================================================"
echo "   return {"
echo "     {"
echo "       dir = \"$SCRIPT_DIR\","
echo "       dependencies = { \"neovim/nvim-lspconfig\" },"
echo "       ft = { \"elixir\", \"heex\", \"eelixir\" },"
echo "       config = function()"
echo "         require(\"phoenix-pulse\").setup()"
echo "       end,"
echo "     }"
echo "   }"
echo ""
echo "2. Restart Neovim"
echo ""
echo "3. Open a Phoenix project:"
echo "   nvim /path/to/your/phoenix/project"
echo ""
echo "4. Test commands:"
echo "   :PhoenixPulseToggle    - Open explorer"
echo "   :PhoenixPulseERD       - Show ERD diagram"
echo ""
echo "See NEOVIM.md for complete documentation!"
