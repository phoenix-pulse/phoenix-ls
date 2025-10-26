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

Phoenix Pulse is a VS Code extension + Node-based language server:

| Layer | Location | Responsibilities |
| --- | --- | --- |
| **Extension host** | `src/` | Boots the LSP, wires document synchronization, exposes commands |
| **Language server** | `lsp/src/server.ts` | Completions, hovers, diagnostics, definitions |
| **Registries** | `lsp/src/*-registry.ts` | Parse workspace for components, controllers, routes, schemas, events |
| **Completions** | `lsp/src/completions/` | Modular providers (components, assigns, JS, routes, etc.) |
| **Diagnostics** | `lsp/src/validators/` | Component issues, navigation problems, JS usage, comment filtering |
| **Grammar** | `syntaxes/` | TextMate grammars for HEEx files and `~H` sigils |

The codebase is TypeScript end-to-end (no Rust or native dependencies).

---

## Quick Start

```bash
git clone https://github.com/phoenix-pulse/phoenix-ls.git
cd phoenix-ls
npm install          # Installs extension + LSP deps (workspaces)
npm run compile      # Builds extension and language server
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
| `npm run compile` | One-shot build for `src/` and `lsp/src/` |
| `npm run watch` | Watch/compile extension bundle (`src/`) |
| `cd lsp && npm run watch` | Watch/compile language server bundle |
| `npm test` | Run vitest suites (`lsp/__tests__`) |
| `npm run compile-ext -- --production` | Production extension build |
| `npm run compile-lsp` | Production server build |
| `npm run package` | Build & package VSIX (uses `vsce`) |

The project uses npm workspaces, so `npm install` at the root installs both extension and LSP dependencies.

---

## Testing & Verification

Before opening a PR:

1. ✅ `npm test` – vitest suites (component diagnostics, controller assigns, comment filters, etc.).
2. ✅ `npm run compile` – ensures TypeScript output is up-to-date.
3. ✅ Manual smoke test in a sample Phoenix project (check completions, hovers, diagnostics).
4. ✅ `NPM_CONFIG_CACHE=./.npm-cache npx vsce package --allow-star-activation --no-dependencies` (if your change touches packaging or grammar).

Optional extras:

- Inspect the “Phoenix Pulse” output channel inside VS Code for registry counts.
- Run `Developer: Reload Window` between test iterations to clear caches.

---

## Pull Request Checklist

- [ ] Follow TypeScript strict mode (no `any` unless justified with comments).
- [ ] Prefer small, focused commits (no generated `out/` or `lsp/dist/` files).
- [ ] Update documentation (README, docs in `docs/`, or inline comments) when behavior changes.
- [ ] Add or update tests when feasible (especially for new registries/completions/diagnostics).
- [ ] Run the VSIX packager if your change affects distribution (grammars, package.json, VS Code contributions).
- [ ] Describe manual verification steps in the PR (e.g., “Typed `<:details>`: saw hover for slot assigns”).

Propose the change in a PR referencing issues when available. Maintainers review for correctness, UX, and performance.

---

## Release Workflow

1. Ensure `npm run compile` and `npm test` pass.
2. `NPM_CONFIG_CACHE=./.npm-cache npx vsce package --allow-star-activation --no-dependencies`.
3. Upload the generated `phoenix-pulse-<version>.vsix` to the release draft.
4. Update release notes & changelog.
5. Publish to the VS Code Marketplace (coming soon).

---

## Code Style & Standards

- TypeScript + ESLint defaults (no implicit `any`, prefer `const`).
- Two-space indentation, single quotes.
- Keep modules cohesive (registries -> `lsp/src/*-registry.ts`, completions -> `lsp/src/completions/`).
- Use helper utilities (`utils/component-usage.ts`, `utils/comments.ts`) to avoid duplication.
- Favor async functions for IO; wrap filesystem access in try/catch.
- Keep docs user-focused: update `README.md`, `PROGRESS_TODAY.md`, and session notes when features ship.

Thanks for contributing—the Phoenix community gets stronger with every PR! 🚀
