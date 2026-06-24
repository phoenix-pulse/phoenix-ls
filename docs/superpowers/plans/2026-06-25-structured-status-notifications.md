# Structured Status Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish structured `phoenix/status` notifications for indexing progress and degraded project-engine state instead of relying only on telemetry.

**Architecture:** Add an LSP status boundary with a custom server-to-client notification struct and pure payload builders. Indexer and manager remain owners of indexing/degraded state and can send status payloads to an opt-in LSP pid. The LSP server receives `{:phoenix_ls_status, payload}` messages and publishes `phoenix/status` over GenLSP.

**Tech Stack:** Elixir, ExUnit, GenLSP notification schemas, existing project manager/indexer processes.

---

### Task 1: Status Notification Contract

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/status_notification.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/status.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/status_test.exs`

- [x] **Step 1: Write failing status contract tests**

Cover `PhoenixLS.LSP.Status.indexing_started/1`, `indexing_completed/1`, and `project_degraded/2` payloads, plus dumping `%PhoenixLS.LSP.StatusNotification{}` to JSON-compatible data with method `phoenix/status`.

- [x] **Step 2: Verify status contract tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/status_test.exs`

- [x] **Step 3: Implement status notification and payload builders**

Add `%PhoenixLS.LSP.StatusNotification{method: "phoenix/status", params: map}` with a Schematic schema using `GenLSP.TypeAlias.LSPAny.schema/0`. Add `PhoenixLS.LSP.Status.publish/2`, `indexing_started/1`, `indexing_completed/1`, and `project_degraded/2`.

- [x] **Step 4: Verify status contract tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/status_test.exs`

### Task 2: Indexer Status Events

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 1: Write failing indexer status tests**

Cover that an indexer started with `root_uri` and `status_target: self()` sends started/completed project indexing status messages, and that `schedule_document/3` with `status_target: self()` sends started/completed document indexing status messages.

- [x] **Step 2: Verify indexer status tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 3: Implement indexer status messages**

Store `root_uri` and `status_target` in indexer state. Send `{:phoenix_ls_status, payload}` for project, document, URI, and delete jobs when a target is present.

- [x] **Step 4: Verify indexer status tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

### Task 3: Manager Degraded Status

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs`

- [x] **Step 1: Write failing manager degraded status test**

Cover `Manager.ensure_engine(manager, root_uri, status_target: self())` with a missing engine supervisor and assert a `phoenix_ls_status` payload with kind `project`, state `degraded`, root URI, and inspected reason.

- [x] **Step 2: Verify manager degraded status test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs`

- [x] **Step 3: Implement manager status target option**

Add optional `status_target` to `ensure_engine/3`, `ensure_project_for_uri/3`, and `restart_engine/3`; send degraded status whenever the manager marks a root degraded or reports backoff.

- [x] **Step 4: Verify manager status tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs`

### Task 4: LSP Transport Wiring

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_events.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/status_transport_test.exs`

- [x] **Step 1: Write failing status transport test**

Start a GenLSP server, initialize with a fixture Mix root, and assert `phoenix/status` notifications for project indexing started and completed.

- [x] **Step 2: Verify status transport test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/status_transport_test.exs`

- [x] **Step 3: Wire status through LSP paths**

Handle `{:phoenix_ls_status, payload}` in `PhoenixLS.LSP.Server` via `PhoenixLS.LSP.Status.publish/2`. Pass `status_target: lsp.pid` through initialize project assignment, workspace folder project discovery, text-document project discovery, watched-file handling, engine startup, and indexer jobs.

- [x] **Step 4: Verify status transport test passes**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/status_transport_test.exs`

### Task 5: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
