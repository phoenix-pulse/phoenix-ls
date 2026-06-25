#!/bin/bash
# Phoenix Pulse Neovim LSP installer tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/install-lsp.sh"
TMP_ROOTS=()

cleanup() {
  for root in "${TMP_ROOTS[@]}"; do
    rm -rf "$root"
  done
}

trap cleanup EXIT

new_root() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/phoenix-ls-nvim-install.XXXXXX")"
  TMP_ROOTS+=("$root")
  echo "$root"
}

copy_installer() {
  local root="$1"
  local plugin_dir="$root/packages/nvim-plugin"

  mkdir -p "$plugin_dir"
  cp "$INSTALLER" "$plugin_dir/install-lsp.sh"
  chmod +x "$plugin_dir/install-lsp.sh"
}

write_fake_executable() {
  local path="$1"
  local label="$2"

  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--help" ]; then
  echo "Usage: phoenix_ls [--stdio]"
  exit 0
fi
echo "$label"
EOF
  chmod +x "$path"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "Expected $file to contain: $expected" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_successfully() {
  local out="$1"
  local err="$2"
  shift 2

  if ! "$@" >"$out" 2>"$err"; then
    echo "Expected command to succeed: $*" >&2
    echo "--- stdout ---" >&2
    cat "$out" >&2
    echo "--- stderr ---" >&2
    cat "$err" >&2
    exit 1
  fi
}

test_uses_existing_bundle_without_mix_or_source() {
  local root plugin_dir out err

  root="$(new_root)"
  plugin_dir="$root/packages/nvim-plugin"
  out="$root/out.log"
  err="$root/err.log"

  copy_installer "$root"
  write_fake_executable "$plugin_dir/server/phoenix_ls" "bundled"

  run_successfully "$out" "$err" env PATH="/usr/bin:/bin" /bin/bash "$plugin_dir/install-lsp.sh"

  assert_contains "$out" "using bundled Phoenix LS executable"
  "$plugin_dir/server/phoenix_ls" --help >/dev/null
}

test_rebuilds_and_replaces_stale_bundle_when_source_is_available() {
  local root plugin_dir server_app_dir fake_bin out err rebuilt_output mix_env

  root="$(new_root)"
  plugin_dir="$root/packages/nvim-plugin"
  server_app_dir="$root/server/apps/phoenix_ls"
  fake_bin="$root/bin"
  out="$root/out.log"
  err="$root/err.log"

  copy_installer "$root"
  write_fake_executable "$plugin_dir/server/phoenix_ls" "stale"

  mkdir -p "$server_app_dir" "$fake_bin"
  cat > "$fake_bin/mix" <<'EOF'
#!/bin/sh
if [ "$1" = "escript.build" ]; then
  printf '%s' "${MIX_ENV:-}" > mix_env.log
  cat > phoenix_ls <<'BIN'
#!/bin/sh
if [ "${1:-}" = "--help" ]; then
  echo "Usage: phoenix_ls [--stdio]"
  exit 0
fi
echo "rebuilt"
BIN
  chmod +x phoenix_ls
  exit 0
fi
exit 64
EOF
  chmod +x "$fake_bin/mix"

  run_successfully "$out" "$err" env PATH="$fake_bin:/usr/bin:/bin" /bin/bash "$plugin_dir/install-lsp.sh"

  assert_contains "$out" "building Phoenix LS escript"
  assert_contains "$out" "Phoenix LS executable installed at:"
  mix_env="$(cat "$server_app_dir/mix_env.log")"
  if [ "$mix_env" != "prod" ]; then
    echo "Expected installer to build with MIX_ENV=prod, got: $mix_env" >&2
    exit 1
  fi
  rebuilt_output="$("$plugin_dir/server/phoenix_ls")"
  if [ "$rebuilt_output" != "rebuilt" ]; then
    echo "Expected rebuilt executable output, got: $rebuilt_output" >&2
    exit 1
  fi
}

test_fails_without_source_mix_or_bundle() {
  local root plugin_dir out err

  root="$(new_root)"
  plugin_dir="$root/packages/nvim-plugin"
  out="$root/out.log"
  err="$root/err.log"

  copy_installer "$root"

  if PATH="/usr/bin:/bin" /bin/bash "$plugin_dir/install-lsp.sh" >"$out" 2>"$err"; then
    echo "Expected installer to fail without source, mix, or bundled executable" >&2
    exit 1
  fi

  assert_contains "$err" "no bundled executable is available"
}

run_test() {
  local name="$1"
  shift

  "$@"
  echo "ok - $name"
}

run_test "uses existing bundle without mix or source" test_uses_existing_bundle_without_mix_or_source
run_test "rebuilds and replaces stale bundle when source is available" test_rebuilds_and_replaces_stale_bundle_when_source_is_available
run_test "fails without source, mix, or bundle" test_fails_without_source_mix_or_bundle
