#!/bin/bash
# Phoenix Pulse Neovim LSP dogfood script tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOGFOOD="$SCRIPT_DIR/dogfood-lsp.sh"
TMP_ROOTS=()

cleanup() {
  for root in "${TMP_ROOTS[@]}"; do
    rm -rf "$root"
  done
}

trap cleanup EXIT

new_root() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/phoenix-ls-nvim-dogfood-test.XXXXXX")"
  TMP_ROOTS+=("$root")
  echo "$root"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq -- "$expected" "$file"; then
    echo "Expected $file to contain: $expected" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

write_fake_nvim() {
  local bin_dir="$1"
  local capture="$2"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/nvim" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$capture"
case " \$* " in
  *" --headless "* ) ;;
  * ) echo "expected --headless" >&2; exit 1 ;;
esac
case " \$* " in
  *" -u NONE "* ) ;;
  * ) echo "expected -u NONE" >&2; exit 1 ;;
esac
case " \$* " in
  *"set runtimepath^="*nvim-lspconfig* ) ;;
  * ) echo "expected nvim-lspconfig runtimepath" >&2; exit 1 ;;
esac
case " \$* " in
  *"set runtimepath^="*nvim-plugin* ) ;;
  * ) echo "expected plugin runtimepath" >&2; exit 1 ;;
esac
case " \$* " in
  *"luafile "*nvim-dogfood.lua* ) ;;
  * ) echo "expected generated dogfood Lua script" >&2; exit 1 ;;
esac
if [ -z "\${PHOENIX_PULSE_COUNTS_FILE:-}" ]; then
  echo "expected PHOENIX_PULSE_COUNTS_FILE" >&2
  exit 1
fi
printf '%s\n' '{"counts":{"phoenix/listSchemas":1,"phoenix/listComponents":1,"phoenix/listRoutes":2,"phoenix/listTemplates":1,"phoenix/listEvents":1,"phoenix/listLiveView":1}}' > "\$PHOENIX_PULSE_COUNTS_FILE"
EOF
  chmod +x "$bin_dir/nvim"
}

test_runs_headless_nvim_against_a_copied_fixture() {
  local root fake_bin capture out err plugin_dir lspconfig_dir fixture_root

  root="$(new_root)"
  fake_bin="$root/bin"
  capture="$root/nvim-args.log"
  out="$root/out.log"
  err="$root/err.log"
  plugin_dir="$root/packages/nvim-plugin"
  lspconfig_dir="$root/nvim-lspconfig"
  fixture_root="$root/fixtures/liveview_components_app"

  mkdir -p "$plugin_dir" "$lspconfig_dir/lua/lspconfig" "$fixture_root"
  cp "$DOGFOOD" "$plugin_dir/dogfood-lsp.sh"
  chmod +x "$plugin_dir/dogfood-lsp.sh"
  cat > "$plugin_dir/install-lsp.sh" <<'EOF'
#!/bin/sh
mkdir -p "$(dirname "$0")/server"
cat > "$(dirname "$0")/server/phoenix_ls" <<'BIN'
#!/bin/sh
exit 0
BIN
chmod +x "$(dirname "$0")/server/phoenix_ls"
echo "installed"
EOF
  chmod +x "$plugin_dir/install-lsp.sh"
  touch "$lspconfig_dir/lua/lspconfig.lua"
  touch "$lspconfig_dir/lua/lspconfig/configs.lua"
  touch "$fixture_root/mix.exs"
  mkdir -p "$fixture_root/lib/app_web/live"
  touch "$fixture_root/lib/app_web/live/page_live.ex"
  write_fake_nvim "$fake_bin" "$capture"

  if ! env PATH="$fake_bin:/usr/bin:/bin" \
    NVIM_LSPCONFIG_ROOT="$lspconfig_dir" \
    PHOENIX_PULSE_FIXTURE_ROOT="$fixture_root" \
    /bin/bash "$plugin_dir/dogfood-lsp.sh" >"$out" 2>"$err"; then
    echo "Expected dogfood script to succeed" >&2
    echo "--- stdout ---" >&2
    cat "$out" >&2
    echo "--- stderr ---" >&2
    cat "$err" >&2
    exit 1
  fi

  assert_contains "$out" "Neovim dogfood passed"
  assert_contains "$out" "phoenix/listSchemas"
  assert_contains "$capture" "--headless"
  assert_contains "$capture" "nvim-dogfood.lua"
}

run_test() {
  local name="$1"
  shift

  "$@"
  echo "ok - $name"
}

run_test "runs headless nvim against a copied fixture" test_runs_headless_nvim_against_a_copied_fixture
