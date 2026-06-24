# Dependency-Aware Diagnostics Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh dependent open HEEx diagnostics after route, component, schema, LiveView, and template index changes instead of only refreshing the edited document.

**Architecture:** Add a pure `PhoenixLS.Index.DependencyGraph` read model that compares before/after URI facts and maps changed fact kinds to affected diagnostics/read-model surfaces. Keep ownership in the project indexer: it computes changed kinds after document, disk URI, and delete jobs, then notifies the LSP process when requested. The LSP diagnostics boundary lists open project documents and schedules debounced diagnostics only for affected HEEx documents.

**Tech Stack:** Elixir, ExUnit, `gen_lsp`, existing `PhoenixLS.Index.Fact`, `PhoenixLS.Index.Store`, `PhoenixLS.Workspace.DocumentStore`, and diagnostics debounce path.

---

### Task 1: Open Document Listing

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document_store.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`

- [x] **Step 1: Write failing document-store listing test**

Add an ExUnit test that opens two documents, calls `DocumentStore.open_documents(__MODULE__.Store)`, and asserts the returned URI list is sorted and contains both documents.

- [x] **Step 2: Verify document-store test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`

- [x] **Step 3: Implement `DocumentStore.open_documents/1`**

Add a public `open_documents/1` GenServer call returning stored `%PhoenixLS.Workspace.Document{}` values sorted by URI.

- [x] **Step 4: Verify document-store test passes**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`

### Task 2: Pure Dependency Graph

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/dependency_graph.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/dependency_graph_test.exs`

- [x] **Step 1: Write failing dependency graph tests**

Cover:
- unchanged facts produce an empty changed-kind set
- route/component/schema/event/template fact changes map to affected read models
- route/component/schema/event changes affect open HEEx diagnostic URIs but ignore non-HEEx documents

- [x] **Step 2: Verify dependency graph tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/dependency_graph_test.exs`

- [x] **Step 3: Implement dependency graph**

Create `changed_kinds/2`, `affected_read_models/1`, and `affected_diagnostic_uris/2`. Compare facts by `{Fact.key(fact), fact.range, fact.data}` so document-version-only provenance churn does not cause dependent refreshes.

- [x] **Step 4: Verify dependency graph tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/dependency_graph_test.exs`

### Task 3: Indexer Change Notifications

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_events.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 1: Write failing indexer notification test**

Add coverage that `Indexer.schedule_document/3` sends `{:phoenix_ls_index_changed, uri, changed_kinds, document_store, project_engine}` after a component fact changes.

- [x] **Step 2: Verify indexer notification test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 3: Implement notification options**

Add optional `diagnostics: {pid, document_store, project_engine}` options to `schedule_document/3`, `schedule_uri/3`, and `delete_uri/3`. Compute before/after URI facts around each indexing operation, derive changed kinds with `DependencyGraph.changed_kinds/2`, and send the message only when the changed-kind set is non-empty.

- [x] **Step 4: Wire watched-file LSP notifications**

Let `FileEvents.handle_lsp_events/3` accept `diagnostics_pid: lsp.pid`, derive the project engine's document store, and pass diagnostics notification options into indexer jobs. Keep filesystem watcher calls on the old two-argument path.

- [x] **Step 5: Verify indexer tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs apps/phoenix_ls/test/phoenix_ls/workspace/file_events_test.exs`

### Task 4: LSP Diagnostics Refresh

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/diagnostics.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

- [x] **Step 1: Write failing transport test**

Add a GenLSP test that opens a component document with a required attr, opens a HEEx document missing that attr, observes the diagnostic, changes the component to remove the required attr, and then expects a cleared diagnostic publish for the still-open HEEx document.

- [x] **Step 2: Verify transport test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

- [x] **Step 3: Implement diagnostics refresh handling**

Handle `{:phoenix_ls_index_changed, uri, changed_kinds, document_store, project_engine}` in `PhoenixLS.LSP.Server` by delegating to `PhoenixLS.LSP.Diagnostics.handle_info/2`. In diagnostics, call `DocumentStore.open_documents/1`, ask `DependencyGraph.affected_diagnostic_uris/2`, and call existing `schedule_publish/4` for each affected URI.

- [x] **Step 4: Pass diagnostics notifications from text sync**

When text sync schedules indexing for open/change/delete jobs with a project engine, pass `diagnostics: {lsp.pid, engine.document_store, {:ok, engine}}` so index completion can refresh dependent HEEx documents after the store is current.

- [x] **Step 5: Verify transport test passes**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

### Task 5: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
