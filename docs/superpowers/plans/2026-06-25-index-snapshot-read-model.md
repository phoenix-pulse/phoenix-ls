# Index Snapshot Read Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route LSP request and diagnostics reads through immutable index snapshots instead of letting request handlers read broad mutable store state directly.

**Architecture:** Add `PhoenixLS.Index.Snapshot` as a small immutable read model built from the engine-owned index store. Extend `PhoenixLS.LSP.RequestContext` with snapshot helpers so request boundaries ask for a project snapshot instead of calling `IndexStore.all/1`. Keep existing feature modules pure by passing `Snapshot.all(snapshot)` until typed read models replace generic facts in a later slice.

**Tech Stack:** Elixir, ExUnit, `gen_lsp`, existing `PhoenixLS.Index.Store`, existing `PhoenixLS.LSP.RequestContext`.

---

### Task 1: Immutable Snapshot API

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/snapshot.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/snapshot_test.exs`

- [x] **Step 1: Write failing snapshot tests**

Cover `from_store/1`, `all/1`, `by_kind/2`, `empty/0`, and immutability after the backing store changes.

- [x] **Step 2: Verify snapshot tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/snapshot_test.exs`

- [x] **Step 3: Implement snapshot module**

Create `%PhoenixLS.Index.Snapshot{facts: list, by_kind: map}`. `from_store/1` reads `PhoenixLS.Index.Store.all/1` once. `all/1` and `by_kind/2` read from the struct only.

- [x] **Step 4: Verify snapshot tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/snapshot_test.exs`

### Task 2: Request Context Snapshot Helpers

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/request_context.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/request_context_test.exs`

- [x] **Step 1: Write failing context tests**

Cover `project_snapshot_for_uri/2` returning a snapshot for a known project and preserving snapshot immutability after the store changes.

- [x] **Step 2: Verify context tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/request_context_test.exs`

- [x] **Step 3: Implement context helper**

Add `project_snapshot_for_uri/2` that reuses `project_engine_for_uri/2` and returns `{:ok, Snapshot.from_store(engine.index_store)}` or `:error`.

- [x] **Step 4: Verify context tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/request_context_test.exs`

### Task 3: Move LSP Boundaries To Snapshots

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/hover.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/definition.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/phoenix_requests.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/diagnostics.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/architecture/read_model_boundary_test.exs`

- [x] **Step 1: Write failing architecture guard**

Scan the LSP boundary files above and assert none call `IndexStore.all(` or `Store.all(` directly. Allow the snapshot module to be the only place that reads all facts for request read models.

- [x] **Step 2: Verify guard fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/architecture/read_model_boundary_test.exs`

- [x] **Step 3: Refactor handlers**

Use `RequestContext.project_snapshot_for_uri/2` in completion, hover, definition, and Phoenix custom requests. Use `Snapshot.from_store/1` inside diagnostics publishing because diagnostics is a notification boundary, not a request context consumer.

- [x] **Step 4: Verify guard and LSP tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/architecture/read_model_boundary_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/hover_transport_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/definition_transport_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

### Task 4: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
