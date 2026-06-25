# Phoenix Pulse AGENTS.md

Project-specific instructions for this repository.

## Rewrite Direction

- This project is moving to a complete Elixir v2 rewrite of the language server.
- Do not optimize for migration from the current TypeScript language server.
- Do not treat current TypeScript behavior as a parity contract.
- Use old TypeScript code only to understand existing pain, user-facing ideas, and feature lessons.
- Prefer clean v2 architecture over preserving old public internals, file layout, or implementation habits.

## Core Architecture

- The language server core should be Elixir-native.
- VS Code remains TypeScript only as an editor launcher/client layer.
- Neovim remains Lua only as an editor launcher/client layer.
- Prefer `gen_lsp` for LSP protocol and transport.
- Use a manager/engine split for project isolation.
- Do not load or execute project code in the manager VM.
- Keep Phoenix, HEEx, Mix, router, schema, LiveView, component, and template intelligence in Elixir.

## Parsing Rules

- Do not use regex to parse Elixir, Phoenix, or HEEx semantics.
- Do not use regex for modules, functions, routers, schemas, components, slots, attributes, events, HEEx tags, HEEx expressions, sigils, or LSP source locations.
- Allowed regex use is limited to non-semantic utilities such as filename checks, test log filtering, or small validation of already-parsed strings.
- Any allowed regex must be local, named, tested, and documented with its reason.

## Code Shape

- Keep modules focused and small.
- Do not create giant server files.
- LSP protocol handling belongs in protocol/transport/dispatcher modules, not feature providers.
- Feature modules should be pure or mostly pure and receive explicit context.
- Every cache must have a clear owner and invalidation path.
- Every indexed fact must include source location and provenance.
- Do not hand-roll LSP UTF-16 position conversion inside feature modules.

## Testing And Verification

- Use ExUnit for the Elixir server.
- Prefer tests around parser behavior, source mapping, indexing, LSP request/response contracts, and degraded-mode behavior.
- Add failing tests before implementation for semantic features.
- Verify with narrow checks first.
- Do not claim behavior works without running the relevant check.

## Long Session Findings - 2026-06-25

- Rewrite tasks 1-7 are complete through commit `9d3b460 test: add performance budget coverage`.
- The completed scope was: custom request edge cases, core LSP feature completeness audit, editor dogfood, real Phoenix app matrix, manager/engine hardening, indexing/invalidation audit, and performance budgets.
- Custom request coverage lives primarily in `server/apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`, `server/apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs`, and `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`.
- LSP feature coverage lives primarily in `server/apps/phoenix_ls/test/phoenix_ls/lsp/*_transport_test.exs` and `server/apps/phoenix_ls/test/phoenix_ls/features/completion/resolve_test.exs`.
- Real project matrix coverage lives in `server/apps/phoenix_ls/test/phoenix_ls/real_project_matrix_test.exs` and covers Phoenix 1.7, Phoenix 1.8, umbrella, LiveView-heavy, broken syntax, non-compiling, missing deps, and large stress fixtures.
- Manager and engine hardening coverage lives in `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`, `server/apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs`, and related compile environment/runner tests.
- Indexing and invalidation coverage lives in `server/apps/phoenix_ls/test/phoenix_ls/index/*_test.exs`, `server/apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs`, and `server/apps/phoenix_ls/test/phoenix_ls/lsp/watched_files_transport_test.exs`.
- Performance budget coverage lives in `server/apps/phoenix_ls/test/phoenix_ls/performance_budget_test.exs`.
- Editor dogfood coverage lives in `packages/vscode-extension/scripts/dogfood-*.js`, `packages/vscode-extension/src/dogfood.ts`, `packages/vscode-extension/src/tree-view-provider.test.ts`, and `packages/nvim-plugin/test-*.lua`.
- Final fresh verification passed with:
  - `mix format --check-formatted "lib/**/*.ex" "test/**/*.exs"` from `server/apps/phoenix_ls`
  - `mix test` from `server/apps/phoenix_ls` with 485 tests
  - `npm run compile --workspace phoenix-pulse`
  - `npm test --workspace phoenix-pulse` with 36 tests
  - `npm test --workspace phoenix-pulse-nvim`
  - `npm run dogfood:server --workspace phoenix-pulse`
  - `npm run dogfood:vscode --workspace phoenix-pulse`
  - `git diff --check`

## Fresh Session Handoff

- Start by checking `git status --short`; at the time this handoff was written, `docs/elixir-v2-scope-matrix.md` already had unrelated local modifications, so do not revert it without explicit user approval.
- Treat tasks 1-7 as completed unless the current worktree, new failures, or new user requirements contradict that state.
- If continuing the rewrite, move to the next unimplemented roadmap area instead of re-auditing the completed 1-7 slice from scratch.
- If modifying behavior touched by tasks 1-7, rerun the relevant narrow test first, then the broader verification command from the list above.

## Git And Scope

- Make the smallest safe change for the current rewrite step.
- Do not do drive-by refactors in the old TypeScript server.
- Do not push unless explicitly requested.
- Keep planning docs and agent instructions tracked even though this repository broadly ignores Markdown.
