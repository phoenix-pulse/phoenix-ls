# Definition Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add LSP go-to-definition for Phoenix source facts that can be resolved from the current cursor classifier.

**Architecture:** Keep symbol matching pure in `PhoenixLS.Features.Definition`; keep document lookup, project routing, and LSP response shape in `PhoenixLS.LSP.Definition`. Reuse existing `PhoenixLS.HEEx.CursorContext` and indexed fact ranges; do not add semantic regex parsing.

**Tech Stack:** Elixir, ExUnit, `gen_lsp`, current source-only Phoenix facts.

---

### Task 1: Pure Definition Provider

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/definition.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/definition_test.exs`

- [x] **Step 1: Write failing feature tests**

Cover definitions for component tags, component attrs, verified route paths, schema fields, and LiveView events.

- [x] **Step 2: Verify feature tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/definition_test.exs`

- [x] **Step 3: Implement minimal pure provider**

Return `GenLSP.Structures.Location` for the matching indexed fact, using fact `uri` and `range`; return `nil` for unsupported cursor contexts.

- [x] **Step 4: Verify feature tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/definition_test.exs`

### Task 2: LSP Wiring

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/definition.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/definition_transport_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`

- [x] **Step 1: Write failing transport and capability tests**

Assert `definitionProvider: true` in initialize and a `textDocument/definition` request returns the component fact location after indexing.

- [x] **Step 2: Wire LSP request**

Dispatch `%GenLSP.Requests.TextDocumentDefinition{}` to `PhoenixLS.LSP.Definition.handle/2` and advertise `definition_provider: true`.

- [x] **Step 3: Verify transport tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/definition_transport_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`

### Task 3: Slice Verification

- [ ] Run `cd server && mix format --check-formatted`
- [ ] Run `cd server && mix test`
- [ ] Run `cd server && mix compile --warnings-as-errors`
- [ ] Run the semantic regex policy scan from the repo root
- [ ] Commit the local slice after verification passes
