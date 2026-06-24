# Hover And Explorer Read Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first shared fact presentation layer for Phoenix hover responses and editor explorer request payloads.

**Architecture:** Keep LSP protocol routing in `PhoenixLS.LSP.*`, keep hover logic pure in `PhoenixLS.Features.Hover`, and introduce small fact presentation helpers that can also serve the custom `phoenix/*` requests. Use current source-only facts and indexed ranges; do not change the parser architecture in this slice.

**Tech Stack:** Elixir, ExUnit, `gen_lsp`, current `PhoenixLS.Index.Fact` facts, no regex semantic parsing.

---

### Task 1: Hover Provider

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/hover.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/hover.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/hover_transport_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`

- [x] **Step 1: Write failing feature tests**

Cover hover content for component tags, component attrs, routes, schema fields, assigns, and LiveView events using current source-only facts.

- [x] **Step 2: Verify feature tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`

- [x] **Step 3: Implement minimal pure hover provider**

Build hover content from `PhoenixLS.HEEx.CursorContext` and `PhoenixLS.Index.Fact` values. Return `nil` for unsupported contexts.

- [x] **Step 4: Verify feature tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`

- [x] **Step 5: Write failing transport and capability tests**

Assert `hoverProvider: true` in initialize and `textDocument/hover` returns a markdown hover from an indexed project.

- [x] **Step 6: Wire LSP hover request**

Add `PhoenixLS.LSP.Hover.handle/2`, dispatch `%GenLSP.Requests.TextDocumentHover{}`, and advertise `hover_provider: true`.

- [x] **Step 7: Verify transport tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/hover_transport_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`

### Task 2: Custom Explorer Requests

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/custom_request.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`

- [x] **Step 1: Write failing feature tests**

Cover `phoenix/listSchemas`, `phoenix/listComponents`, `phoenix/listRoutes`, `phoenix/listTemplates`, `phoenix/listEvents`, and `phoenix/listLiveView` payloads using the same indexed facts.

- [x] **Step 2: Verify feature tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`

- [x] **Step 3: Implement pure request payload builders**

Map indexed facts to stable editor-facing maps with source uri/range/provenance, grouped details, and no old TypeScript parity shims.

- [x] **Step 4: Verify feature tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`

- [x] **Step 5: Wire request boundary**

Add a local request struct or protocol extension point so custom `phoenix/*` requests reach `PhoenixLS.LSP.Dispatcher` without feature modules depending on transport internals.

- [x] **Step 6: Verify custom request tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`

### Task 3: Slice Verification

- [ ] Run `cd server && mix format --check-formatted`
- [ ] Run `cd server && mix test`
- [ ] Run `cd server && mix compile --warnings-as-errors`
- [ ] Run the semantic regex policy scan from the repo root
- [ ] Commit the local slice after verification passes
