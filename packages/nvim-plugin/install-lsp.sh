#!/bin/bash
# Phoenix Pulse Neovim Plugin - Phoenix LS escript installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_APP_DIR="$SCRIPT_DIR/../../server/apps/phoenix_ls"
SOURCE="$SERVER_APP_DIR/phoenix_ls"
TARGET_DIR="$SCRIPT_DIR/server"
TARGET="$TARGET_DIR/phoenix_ls"

verify_executable() {
  local candidate="$1"

  if [ ! -f "$candidate" ]; then
    return 1
  fi

  chmod +x "$candidate" 2>/dev/null || true

  if [ ! -x "$candidate" ]; then
    echo "Error: Phoenix LS executable is not executable: $candidate" >&2
    return 1
  fi

  if ! "$candidate" --help >/dev/null 2>&1; then
    echo "Error: Phoenix LS executable failed validation: $candidate" >&2
    return 1
  fi
}

if [ -d "$SERVER_APP_DIR" ] && command -v mix >/dev/null 2>&1; then
  echo "Phoenix Pulse: building Phoenix LS escript..."
  (
    cd "$SERVER_APP_DIR"
    MIX_ENV=prod mix escript.build
  )

  if [ ! -f "$SOURCE" ]; then
    echo "Error: mix escript.build did not produce $SOURCE" >&2
    exit 1
  fi

  mkdir -p "$TARGET_DIR"
  cp "$SOURCE" "$TARGET"
  chmod +x "$TARGET"

  verify_executable "$TARGET"

  echo "Phoenix LS executable installed at: $TARGET"
  exit 0
fi

if verify_executable "$TARGET"; then
  echo "Phoenix Pulse: using bundled Phoenix LS executable at: $TARGET"
  exit 0
fi

if [ ! -d "$SERVER_APP_DIR" ]; then
  echo "Error: Phoenix LS source not found at $SERVER_APP_DIR and no bundled executable is available at: $TARGET" >&2
  exit 1
fi

echo "Error: mix is not installed. Install Elixir before building Phoenix LS, or provide a bundled executable at: $TARGET" >&2
exit 1
