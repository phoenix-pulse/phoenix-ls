# Phoenix Pulse Release Guide

This guide covers local release-candidate packaging for the Elixir v2 server and editor clients. It does not publish, push, or tag anything.

## Requirements

- Elixir 1.17 and Erlang/OTP 27 for the Phoenix LS escript.
- Node.js 20 and npm for VS Code packaging.
- VS Code 1.75 or newer for extension installs.
- Neovim 0.8 or newer with `nvim-lspconfig` for the Neovim plugin.

## Build Artifacts

Install dependencies from the repository root:

```bash
npm ci
cd server
mix deps.get
cd ..
```

Build the VS Code package:

```bash
npm run package:vscode
```

This runs the VS Code prepublish hook, builds `server/apps/phoenix_ls/phoenix_ls` with `MIX_ENV=prod`, copies it to `packages/vscode-extension/server/phoenix_ls`, and writes `packages/vscode-extension/phoenix-pulse-1.4.0.vsix`.

Build or update the Neovim executable:

```bash
npm run update-lsp --workspace phoenix-pulse-nvim
```

This runs `packages/nvim-plugin/install-lsp.sh`. The script rebuilds from source when Mix and the server source are available. If a packaged install already includes `packages/nvim-plugin/server/phoenix_ls`, the same script validates and uses that bundled executable.

## VS Code Install

Install a local VSIX:

```bash
code --install-extension packages/vscode-extension/phoenix-pulse-1.4.0.vsix --force
```

The extension resolves the Phoenix LS executable in this order:

1. `phoenixPulse.serverPath`
2. `PHOENIX_LS_SERVER_PATH`
3. bundled `server/phoenix_ls`
4. bundled `bin/phoenix_ls`
5. monorepo development build at `server/apps/phoenix_ls/phoenix_ls`

Useful VS Code settings:

```json
{
  "phoenixPulse.serverPath": "/absolute/path/to/phoenix_ls",
  "phoenixPulse.sourceOnlyMode": true,
  "phoenixPulse.logLevel": "info",
  "phoenixPulse.indexing.enabled": true
}
```

Open logs with `View: Toggle Output`, then select `Phoenix Pulse`. The output includes activation messages, project detection, the resolved executable path, LSP state changes, and startup errors. Use `Developer: Toggle Developer Tools` for extension-side console logs.

## Neovim Install

For a local checkout:

```lua
{
  dir = "~/phoenix-ls/packages/nvim-plugin",
  build = "./install-lsp.sh",
  dependencies = { "neovim/nvim-lspconfig" },
  ft = { "elixir", "heex", "eelixir" },
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

Custom server path and runtime options:

```lua
require("phoenix-pulse").setup({
  lsp_server_path = "/absolute/path/to/phoenix_ls",
  source_only_mode = true,
  log_level = "info",
  indexing_enabled = true,
})
```

The plugin auto-detects:

1. `packages/nvim-plugin/server/phoenix_ls`
2. `packages/nvim-plugin/bin/phoenix_ls`
3. monorepo development build at `server/apps/phoenix_ls/phoenix_ls`

Check Neovim status and logs:

```vim
:messages
:lua vim.print(vim.lsp.get_active_clients({ name = "phoenix_pulse" }))
:lua vim.lsp.set_log_level("debug")
:edit ~/.local/state/nvim/lsp.log
```

On Neovim versions that use a different state directory, inspect it with:

```vim
:lua print(vim.fn.stdpath("state"))
```

## Troubleshooting

Executable missing:

```bash
npm run package:vscode
npm run update-lsp --workspace phoenix-pulse-nvim
packages/vscode-extension/server/phoenix_ls --help
packages/nvim-plugin/server/phoenix_ls --help
```

VS Code reports `Phoenix LS executable not found`:

- Check the `Phoenix Pulse` output channel for the list of paths that were tried.
- Set `phoenixPulse.serverPath` to an absolute `phoenix_ls` path.
- Rebuild the VSIX if `packages/vscode-extension/server/phoenix_ls` is missing.

Neovim reports `LSP server not found`:

- Run `cd packages/nvim-plugin && ./install-lsp.sh`.
- Set `lsp_server_path` to an absolute `phoenix_ls` path.
- Confirm `packages/nvim-plugin/server/phoenix_ls --help` exits successfully.

No completions or diagnostics:

- Confirm the filetype is `elixir`, `heex`, or `eelixir`.
- Confirm the workspace contains a `mix.exs`.
- Keep `indexing_enabled` / `phoenixPulse.indexing.enabled` set to `true`.
- Check the editor logs for degraded-mode or indexing status messages.

Explorer or ERD data is empty:

- Run `PhoenixPulseRefresh` in Neovim or `Refresh Explorer` / `phoenixPulse.refreshExplorer` in VS Code.
- Confirm the server is running before invoking explorer commands.
- Check logs for failed `phoenix/listSchemas`, `phoenix/listComponents`, `phoenix/listRoutes`, `phoenix/listTemplates`, `phoenix/listEvents`, or `phoenix/listLiveView` requests.

## Local Verification

Run these before publishing release artifacts:

```bash
cd server
mix format --check-formatted
mix test
cd apps/phoenix_ls
MIX_ENV=prod mix escript.build
./phoenix_ls --help
cd ../../..

npm run compile:vscode
npm test --workspace phoenix-pulse
npm run package:vscode

npm test --workspace phoenix-pulse-nvim
bash -n packages/nvim-plugin/install-lsp.sh packages/nvim-plugin/test-install-lsp.sh packages/nvim-plugin/test-plugin.sh
luac -p packages/nvim-plugin/lua/phoenix-pulse/*.lua packages/nvim-plugin/plugin/phoenix-pulse.lua
npm run update-lsp --workspace phoenix-pulse-nvim
packages/nvim-plugin/server/phoenix_ls --help
```

The GitHub Actions workflow in `.github/workflows/ci.yml` runs the same release-candidate gates on pull requests and pushes to `main`.
