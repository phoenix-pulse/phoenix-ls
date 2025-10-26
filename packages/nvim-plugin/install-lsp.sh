#!/bin/bash
# Phoenix Pulse Neovim Plugin - LSP Installer
# This script installs the language server from npm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Phoenix Pulse: Installing LSP server from npm..."

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ Error: npm is not installed"
    echo "   Please install Node.js and npm first"
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

# Navigate to plugin directory
cd "$SCRIPT_DIR"

# Install dependencies (language server from npm)
echo "Running npm install..."
npm install

# Verify installation
LSP_PATH="$SCRIPT_DIR/node_modules/@phoenix-pulse/language-server/dist/server.js"
if [ -f "$LSP_PATH" ]; then
    echo "✅ LSP server installed successfully!"
    echo "   Location: $LSP_PATH"
else
    echo "❌ Error: LSP server installation failed"
    echo "   Expected at: $LSP_PATH"
    exit 1
fi
