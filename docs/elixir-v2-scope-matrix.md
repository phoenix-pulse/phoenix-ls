# PhoenixLS Elixir v2 Scope Matrix

This is not a migration or parity checklist. The old TypeScript server is not a contract.

## Status Values

- `build-now`: required for the first usable v2 foundation or core feature set
- `later`: valuable after the core server is stable
- `out-of-scope`: intentionally not part of v2

## Foundation

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| Elixir umbrella under `server/` | build-now | Clean v2 server home | Mix compile and application smoke test |
| GenLSP lifecycle | build-now | initialize/shutdown/document sync foundation | JSON-RPC or GenLSP callback tests |
| Document store | build-now | Open editor buffers are source of truth | open/change/close tests |
| UTF-16 position conversion | build-now | Required for all LSP ranges | Unicode, CRLF, HEEx offset tests |
| Regex enforcement | build-now | Prevent semantic regex parsing | architecture policy test |

## Core Phoenix Intelligence

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| HEEx cursor context | build-now | Needed before completions | parser/cursor fixture tests |
| Function component extraction | build-now | Component completions and definitions | fixture component tests |
| Attribute and slot extraction | build-now | Component attribute/slot completions | fixture component tests |
| Router extraction | build-now | Verified route completions | Phoenix fixture tests |
| Schema extraction | build-now | Form/schema completions | Ecto fixture tests |
| LiveView event extraction | build-now | `phx-*` event completions | LiveView fixture tests |
| Diagnostics | build-now | Start with high-signal Phoenix mistakes | feature diagnostics tests |

## Editor Surfaces

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| VS Code launcher | later | TypeScript client only, Elixir server core | extension activation smoke test |
| Neovim launcher | later | Lua client only, Elixir server core | local nvim config smoke test |
| Project explorer UI | later | Rebuild only if v2 custom requests justify it | custom request contract tests |
| ERD viewer | later | Not foundation work | explicit feature tests if rebuilt |

## Explicitly Out Of Scope For Foundation

| Area | Status | Reason |
| --- | --- | --- |
| TypeScript server migration | out-of-scope | Clean Elixir v2 rewrite |
| Old behavior parity | out-of-scope | v2 design owns behavior |
| Regex semantic parser | out-of-scope | Parser APIs and AST only |
| Go server core | out-of-scope | Phoenix semantics belong in Elixir |
