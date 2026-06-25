#!/bin/bash
# Phoenix Pulse Neovim Plugin - Phoenix LS escript installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_APP_DIR="$SCRIPT_DIR/../../server/apps/phoenix_ls"
TARGET_DIR="$SCRIPT_DIR/server"
TARGET="$TARGET_DIR/phoenix_ls"

if ! command -v mix >/dev/null 2>&1; then
  echo "Error: mix is not installed. Install Elixir before building Phoenix LS." >&2
  exit 1
fi

if [ ! -d "$SERVER_APP_DIR" ]; then
  echo "Error: Phoenix LS source not found at $SERVER_APP_DIR" >&2
  exit 1
fi

echo "Phoenix Pulse: building Phoenix LS escript..."
(
  cd "$SERVER_APP_DIR"
  mix escript.build
)

mkdir -p "$TARGET_DIR"
cp "$SERVER_APP_DIR/phoenix_ls" "$TARGET"
chmod +x "$TARGET"

echo "Phoenix LS executable installed at: $TARGET"
