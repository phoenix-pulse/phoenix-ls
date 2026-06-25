# Contributing to Phoenix Pulse

Thanks for helping shape Phoenix Pulse! This guide covers project expectations, local setup, testing, and how to ship a polished contribution.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Quick Start](#quick-start)
3. [Development Workflow](#development-workflow)
4. [Testing & Verification](#testing--verification)
5. [Pull Request Checklist](#pull-request-checklist)
6. [Release Workflow](#release-workflow)
7. [Code Style & Standards](#code-style--standards)

---

## Project Overview

Phoenix Pulse is an Elixir-native language server with thin editor clients:

| Layer | Location | Responsibilities |
| --- | --- | --- |
| **Elixir server** | `server/apps/phoenix_ls/lib/phoenix_ls/` | LSP protocol, project management, indexing, Phoenix introspection, completions, hovers, diagnostics, definitions, signature help, and code actions |
| **Manager/project engine** | `server/apps/phoenix_ls/lib/phoenix_ls/project/` | Project isolation, degraded state, restart/backoff behavior, and engine-owned indexing |
| **Index and facts** | `server/apps/phoenix_ls/lib/phoenix_ls/index/` | Source facts, snapshots, dependency-aware invalidation, project scans |
| **VS Code client** | `packages/vscode-extension/src/` | Launches `phoenix_ls`, exposes settings, explorer, ERD, and VS Code commands |
| **Neovim client** | `packages/nvim-plugin/lua/phoenix-pulse/` | Launches `phoenix_ls`, exposes Lua config, explorer, ERD, and Neovim commands |
| **Grammar** | `packages/vscode-extension/syntaxes/` | TextMate grammars for HEEx files and `~H` sigils |

Do not implement new Phoenix semantics in the legacy TypeScript server. The TypeScript and Lua code should stay editor-client focused.

---

## Quick Start

```bash
git clone https://github.com/phoenix-pulse/phoenix-ls.git
cd phoenix-ls
npm install          # Installs extension + LSP deps (workspaces)
cd server
mix deps.get
mix test
cd ..
npm run compile:vscode
```

Run the extension in VS Code:

1. `code .`
2. Press `F5` to launch the Extension Development Host.
3. Open a Phoenix project in the new window to test completions/diagnostics.

---

## Development Workflow

Common scripts (run from repo root unless noted):

| Command | Purpose |
| --- | --- |
| `cd server && mix test` | Run Elixir server tests |
| `cd server && mix format --check-formatted` | Check Elixir formatting |
| `npm run compile:vscode` | Build the VS Code client bundle |
| `npm test --workspace phoenix-pulse` | Run VS Code client, explorer, ERD, and packaging-helper tests |
| `npm test --workspace phoenix-pulse-nvim` | Run Neovim installer and Lua contract tests |
| `npm run package:vscode` | Build the Elixir escript, bundle it into the VS Code extension, and package a VSIX |
| `npm run update-lsp --workspace phoenix-pulse-nvim` | Build or validate the Neovim bundled `phoenix_ls` executable |

The project uses npm workspaces for editor tooling. Elixir dependencies are managed separately under `server/`.

---

## Testing & Verification

Before opening a PR:

1. ✅ `cd server && mix format --check-formatted && mix test` for server changes.
2. ✅ `cd server/apps/phoenix_ls && MIX_ENV=prod mix escript.build && ./phoenix_ls --help` for executable changes.
3. ✅ `npm run compile:vscode && npm test --workspace phoenix-pulse` for VS Code changes.
4. ✅ `npm test --workspace phoenix-pulse-nvim` for Neovim changes.
5. ✅ `npm run package:vscode` if your change touches packaging, the server executable, grammar, or VS Code contributions.
6. ✅ Manual smoke test in a sample Phoenix project for user-facing LSP behavior.

Optional extras:

- Inspect the “Phoenix Pulse” output channel inside VS Code for registry counts.
- Run `Developer: Reload Window` between test iterations to clear caches.
- Use `:messages` and Neovim LSP logs when testing the Neovim client.

---

## Pull Request Checklist

- [ ] Keep semantic Phoenix, HEEx, router, schema, template, and LiveView logic in Elixir.
- [ ] Keep VS Code TypeScript and Neovim Lua changes focused on launcher/client/UI behavior.
- [ ] Prefer small, focused commits (no generated `out/`, `_build/`, `deps/`, or packaged artifacts unless intentionally updating a bundled executable).
- [ ] Update documentation (README, docs in `docs/`, or inline comments) when behavior changes.
- [ ] Add or update tests before implementing semantic behavior.
- [ ] Run the VSIX packager if your change affects distribution (grammars, package.json, VS Code contributions).
- [ ] Describe manual verification steps in the PR (e.g., “Typed `<:details>`: saw hover for slot assigns”).

Propose the change in a PR referencing issues when available. Maintainers review for correctness, UX, and performance.

---

## Release Workflow

1. Ensure the Elixir server, VS Code client, and Neovim plugin checks pass.
2. `npm run package:vscode`.
3. Upload the generated `phoenix-pulse-<version>.vsix` to the release draft.
4. Update release notes & changelog.
5. Publish only through the approved release process.

---

## Code Style & Standards

- Elixir server code uses ExUnit tests, focused modules, explicit context, and source locations/provenance for indexed facts.
- Do not use regex to parse Elixir, Phoenix, or HEEx semantics.
- Do not put LSP protocol handling inside feature providers.
- Do not load or execute project code in the manager VM.
- TypeScript and Lua client code should remain thin launcher/UI layers around the Elixir server.
- Keep docs user-focused: update `README.md`, `NEOVIM.md`, `docs/release.md`, and package READMEs when behavior changes.

Thanks for contributing—the Phoenix community gets stronger with every PR! 🚀
