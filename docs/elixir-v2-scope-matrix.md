# PhoenixLS Elixir v2 Scope Matrix

This is a Phoenix companion-server scope matrix. The old TypeScript server is
evidence only; v2 is not a migration checklist.

Final implementation order lives in
`docs/superpowers/plans/2026-06-25-phoenix-ls-final-100-percent-completion-plan.md`.
Detailed evidence lives in `docs/phoenix-ls-feature-evidence-matrix.md`.

## Status Values

- `done`: implemented and covered by focused tests in the Elixir v2 server or
  editor layer
- `partial`: useful behavior exists, with intentionally conservative or future
  maintenance areas left
- `planned`: separately scoped future work remains
- `non-goal`: intentionally outside the v2 Phoenix companion scope

## Ownership Values

- `phoenix-ls`: Phoenix LS owns this capability in all modes
- `expert`: Expert owns this capability when Phoenix LS runs in companion mode
- `shared`: Phoenix LS may answer only in Phoenix-specific contexts

## Foundation

| Area | Status | Owner | Notes | Evidence |
| --- | --- | --- | --- | --- |
| Elixir umbrella under `server/` | done | phoenix-ls | Clean v2 server home | `server/apps/phoenix_ls`, `application_test.exs` |
| GenLSP lifecycle and dispatcher | done | phoenix-ls | initialize, shutdown, dispatch, runtime, status | `lsp/*_test.exs` |
| Document store and sync | done | phoenix-ls | Open buffers are source of truth | `workspace/*_test.exs`, `document_sync_transport_test.exs` |
| UTF-16 source mapping | done | phoenix-ls | Centralized source map helpers | `parsing/source_map_test.exs`, `support/positions_test.exs` |
| Semantic parsing policy | done | phoenix-ls | Architecture guard against semantic regular-expression parsing | `architecture/regex_policy_test.exs` |
| Manager/engine split | done | phoenix-ls | Project isolation and degraded mode | `project/manager_test.exs`, `project/engine_status_test.exs` |
| Index invalidation | done | phoenix-ls | Stale facts are removed on change/delete | `index/invalidation_test.exs`, sync transport tests |
| Performance budgets | done | phoenix-ls | Budget tests exist for v2 facts | `performance_budget_test.exs` |
| Companion mode policy | done | phoenix-ls | Generic behavior suppressed with Expert | `features/policy_test.exs`, `lsp/mode_test.exs` |
| Expert detection settings | done | phoenix-ls | VS Code and Neovim mode resolution | editor tests |

## Core Phoenix Intelligence

| Area | Status | Owner | Notes | Remaining work |
| --- | --- | --- | --- | --- |
| HEEx parser and cursor context | done | phoenix-ls | Source-ranged tags, attrs, expressions, and cursor classification | Keep using shared source map helpers |
| Function component extraction | done | phoenix-ls | Component facts from source | Keep docs and generated app coverage current |
| Attr and slot extraction | done | phoenix-ls | Attr, slot, and slot-attr facts include ranges/provenance | Keep rich docs/snippets current |
| Component completions | done | phoenix-ls | Tags, attrs, slots, and slot attrs | Keep generated/built-in coverage current |
| Component hover/definition/signature help | done | shared | Source-ranged Phoenix contexts covered | Keep docs shared across providers |
| Component diagnostics and quick fixes | done | phoenix-ls | Required attrs/slots, unknown attrs/slots, invalid values | Keep diagnostics high confidence |
| Built-in components | done | phoenix-ls | Built-in completions, docs, hover, and resolve paths exist | Keep generated component docs current |
| Special HEEx attrs | done | phoenix-ls | `:for`, `:if`, `:let`, `:key`, and special attrs covered | Keep parser-backed only |
| Scoped HEEx variables | partial | phoenix-ls | Parsed scope and schema-backed loop support exist | Keep expanding only from parsed facts |
| Router extraction | done | phoenix-ls | Routes, resources, match, scopes, forwards, live routes, sessions | Controller graph links covered where static |
| Verified routes and helpers | done | phoenix-ls | `~p` and legacy route helper completions/diagnostics | Keep Phoenix-specific only |
| Template indexing and references | done | phoenix-ls | Template facts, missing reference diagnostics, and controller binding exist | Keep exact references source-ranged |
| Controller action/render/assign/layout/plug graph | done | phoenix-ls | Routes, actions, renders, templates, assigns, layouts, and plug assigns covered | Keep dynamic cases conservative |
| Schema extraction | done | phoenix-ls | Fields, associations, embeds, primary keys, foreign keys | Keep changeset/form links exact |
| Form field completions | partial | phoenix-ls | Schema-aware form completions exist | Continue conservative nested/embedded/generated form expansion |
| Changeset facts | partial | phoenix-ls | Source facts exist for validations and form authoring | Keep diagnostics exact-only |
| LiveView event extraction | done | phoenix-ls | Literal `handle_event/3` and HEEx usage facts | Keep JS event links fact-backed |
| LiveView assign extraction | partial | phoenix-ls | Direct assigns, streams, uploads, async assigns | Continue advanced lifecycle/message expansion from source facts |
| Streams | done | phoenix-ls | Stream diagnostics and quick fixes exist | Keep source-only and conservative |
| Upload intelligence | partial | phoenix-ls | Static upload names and template usage covered | Keep callback inference conservative |
| Hook intelligence | partial | phoenix-ls | Asset and colocated hook facts covered | Keep LiveView version behavior current |
| Colocated JS/CSS/hook intelligence | partial | phoenix-ls | Phoenix fact extraction exists | Keep source fixture verification current |
| Live navigation diagnostics | done | phoenix-ls | Route/live session aware diagnostics and actions | Keep dynamic paths quiet |
| `Phoenix.LiveView.JS` completions | done | phoenix-ls | Commands, options, pipe chains, and trigger contexts covered | Keep command list current |
| Phoenix attr ranking | done | phoenix-ls | Context-aware attrs, docs, and snippets exist | Keep docs current |
| Phoenix explorer requests | done | phoenix-ls | Schemas, components, routes, templates, events, LiveView, uploads, hooks, colocated assets, and controllers work | Keep payloads source-ranged |

## Editor Surfaces

| Area | Status | Owner | Notes | Remaining work |
| --- | --- | --- | --- | --- |
| VS Code launcher | done | phoenix-ls | TypeScript launcher/client only | Installed VSIX dogfood covered |
| VS Code Expert detection | done | phoenix-ls | Best-effort detection and explicit mode | Keep tests current |
| Neovim launcher | done | phoenix-ls | Lua launcher/client only | Dogfood covered |
| Neovim Expert detection | done | phoenix-ls | Active/configured Expert detection | Keep tests current |
| Project explorer UI | done | phoenix-ls | Current custom request payloads include controller graph | Keep presentation client-owned |
| ERD/project graph | partial | phoenix-ls | Phoenix facts can support this | Keep outside final gate unless fact-backed |

## Expert-Owned Generic Elixir Behavior

| Area | Status | Owner | Companion mode behavior |
| --- | --- | --- | --- |
| Generic Elixir completion | non-goal | expert | Phoenix LS returns no generic fallback results |
| Generic Elixir hover | non-goal | expert | Phoenix LS returns nil outside Phoenix contexts |
| Generic Elixir definition | non-goal | expert | Phoenix LS returns nil outside Phoenix contexts |
| Generic references | non-goal | expert | Phoenix LS does not advertise or implement |
| Generic rename | non-goal | expert | Phoenix LS does not advertise or implement |
| Formatting | non-goal | expert | Phoenix LS does not advertise or implement |
| Compiler diagnostics | non-goal | expert | Phoenix LS publishes only Phoenix-specific diagnostics |
| Generic symbols and outline | non-goal | expert | Phoenix LS does not advertise or implement |
| Semantic tokens | non-goal | expert | Phoenix LS does not advertise or implement |
| Generic code actions | non-goal | expert | Phoenix LS returns only Phoenix quick fixes |

## Final Gates

| Gate | Status | Notes |
| --- | --- | --- |
| Feature evidence matrix | done | Current ledger exists and is updated |
| Complex Phoenix 1.8 fixture | done | Real project matrix and dogfood fixture covered |
| Installed VSIX dogfood | done | `phoenix-pulse-1.4.0.vsix` packaged and installed |
| Old TypeScript evidence closure | done | Old TS server removed; evidence retained in docs |
| DRY, size, semantic parsing, and performance audit | done | Regex policy, performance budget, and verification checks covered |
| Full final verification | done | See latest verification command list in handoff/final response |

## Explicit Non-Goals

| Area | Reason |
| --- | --- |
| TypeScript server migration | Clean Elixir v2 rewrite |
| Old behavior parity | v2 owns its Phoenix companion design |
| Semantic parsing with ad-hoc string matching | Parser APIs, quoted AST, and source-ranged facts only |
| Go server core | Phoenix semantics belong in Elixir |
| Expert replacement | Phoenix LS complements Expert instead of replacing it |
| Emmet ownership | VS Code client maps `phoenix-heex` to `html`; the Elixir server does not own Emmet |
| Generic HTML language-service behavior | VS Code client forwards `.heex` and `~H` regions to HTML providers; Phoenix LS stays focused on HEEx and Phoenix facts |
| General JavaScript/CSS analysis | VS Code client forwards `<script>`/`<style>` regions; server-side colocated assets remain Phoenix facts, not broad JS/CSS analysis |
