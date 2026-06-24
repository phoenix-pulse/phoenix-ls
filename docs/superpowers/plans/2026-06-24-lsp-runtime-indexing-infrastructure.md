# LSP Runtime And Indexing Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the runtime entrypoint and indexing infrastructure needed for the remaining v2 LSP feature work.

**Architecture:** Keep `PhoenixLS.LSP.Server` as the GenLSP callback boundary, but move request and notification routing into `PhoenixLS.LSP.Dispatcher` with an explicit `PhoenixLS.LSP.RequestContext`. Start the editor-facing server through a small runtime supervisor that owns GenLSP buffer, assigns, task supervisor, and server processes. Move project indexing writes behind an engine-owned background indexer plus explicit invalidation helpers, and route watched file notifications through one file-event ingestion module.

**Tech Stack:** Elixir, ExUnit, GenLSP, OTP supervisors/GenServers, existing source-only Elixir AST indexing.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/cli.ex`
  - Escript main module.
  - Supports `--stdio`, default no-arg stdio mode, `--version`, and `--help`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/runtime.ex`
  - Starts GenLSP buffer, assigns, task supervisor, and `PhoenixLS.LSP.Server`.
  - Defaults to `GenLSP.Communication.Stdio`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
  - Owns LSP request/notification routing.
  - Keeps lifecycle, completion, text document sync, workspace folders, and watched file changes out of `Server`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/request_context.ex`
  - Snapshots LSP assigns and exposes known project/engine helpers for request modules.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/invalidation.ex`
  - Explicit invalidation API for deleting indexed facts by URI.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
  - Engine-owned background worker for document and disk-file reindex jobs.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_events.ex`
  - Handles `workspace/didChangeWatchedFiles` events and normalized filesystem events.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_watcher.ex`
  - Optional `file_system` subscriber that forwards filesystem events into `FileEvents`.
- Modify `server/apps/phoenix_ls/mix.exs`
  - Add escript main module.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
  - Supervise one `Index.Indexer` per project engine.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
  - Add stable indexer process names.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Delegate routing to the configured dispatcher.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
  - Accept `RequestContext` instead of reading raw assigns directly.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
  - Schedule indexing through the engine indexer and invalidation layer.

## Task 1: Runtime Entrypoint

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/cli.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/runtime.ex`
- Modify: `server/apps/phoenix_ls/mix.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/cli_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs`

- [x] **Step 1: Write failing CLI and runtime tests**

Assert:
- `PhoenixLS.MixProject.project()[:escript][:main_module] == PhoenixLS.CLI`
- `PhoenixLS.CLI.main(["--version"])` prints `PhoenixLS 0.1.0`
- `PhoenixLS.CLI.main(["--help"])` prints usage text containing `--stdio`
- `PhoenixLS.LSP.Runtime.start_link/1` starts a supervisor with configured GenLSP process names and a test communication adapter

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/cli_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs
```

Expected: FAIL because `PhoenixLS.CLI` and `PhoenixLS.LSP.Runtime` do not exist and escript config is absent.

- [x] **Step 3: Implement CLI, runtime supervisor, and escript config**

`PhoenixLS.CLI.main/1` handles `--version`, `--help`, `--stdio`, and no args. Stdio mode ensures `:phoenix_ls` is started, starts `PhoenixLS.LSP.Runtime`, and sleeps forever.

`PhoenixLS.LSP.Runtime.start_link/1` starts:
- `GenLSP.Buffer`
- `GenLSP.Assigns`
- `Task.Supervisor`
- `PhoenixLS.LSP.Server`

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/cli_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs
```

Expected: PASS.

## Task 2: Dispatcher And Request Context

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/request_context.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/dispatcher_test.exs`
- Test: existing lifecycle and completion LSP tests

- [x] **Step 1: Write failing dispatcher and context tests**

Assert:
- `RequestContext.new/1` snapshots LSP assigns and exposes known project roots in longest-prefix order.
- `Server.handle_request/2` delegates to the dispatcher configured during `Server.init/2`.
- `Server.handle_notification/2` delegates to the dispatcher configured during `Server.init/2`.
- `Dispatcher.handle_request/2` preserves existing initialize, shutdown, and completion behavior.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/dispatcher_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: FAIL because dispatcher/context modules and delegation do not exist.

- [x] **Step 3: Implement dispatcher and context**

Move routing clauses from `PhoenixLS.LSP.Server` into `PhoenixLS.LSP.Dispatcher`. Keep `Server` responsible for GenLSP `start_link/1`, `init/2`, and delegation only.

Update `PhoenixLS.LSP.Completion` to receive a `RequestContext` and use context helpers for project root and engine lookup.

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/dispatcher_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: PASS.

## Task 3: Explicit Invalidation And Background Reindexing

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/invalidation.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/invalidation_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`
- Test: existing text document sync tests

- [x] **Step 1: Write failing invalidation and indexer tests**

Assert:
- `Invalidation.invalidate_uri/2` deletes all facts for a URI and returns `:ok`.
- `Index.Indexer.schedule_document/2` asynchronously reindexes an open Elixir document.
- `Index.Indexer.schedule_uri/2` reads an `.ex` file from disk by URI and indexes it.
- `Index.Indexer.delete_uri/2` invalidates facts for deleted/closed files.
- Project engines expose a named indexer process.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/invalidation_test.exs apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
```

Expected: FAIL because invalidation/indexer modules and engine wiring do not exist.

- [x] **Step 3: Implement invalidation, background indexer, and text-sync scheduling**

`Index.Indexer` is a GenServer owned by `Project.Engine`. It receives casts for document indexing, disk URI indexing, and delete/invalidate jobs. `TextDocumentSync` schedules jobs instead of writing index facts directly.

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/invalidation_test.exs apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
```

Expected: PASS.

## Task 4: Watched File And Optional Filesystem Event Ingestion

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_events.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_watcher.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/workspace/file_events_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/workspace/file_watcher_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/watched_files_transport_test.exs`

- [x] **Step 1: Write failing file-event tests**

Assert:
- LSP `workspace/didChangeWatchedFiles` changed/created events schedule disk reindex for the owning project.
- LSP deleted events invalidate facts for the URI.
- Non-project URIs are ignored without crashing.
- File-system events like `{path, [:modified]}` and `{path, [:deleted]}` normalize to the same ingestion path.
- `FileWatcher` starts a `file_system` worker when dirs are configured and forwards received file events to `FileEvents`.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/file_events_test.exs apps/phoenix_ls/test/phoenix_ls/workspace/file_watcher_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/watched_files_transport_test.exs
```

Expected: FAIL because file event modules and watched-file dispatch do not exist.

- [x] **Step 3: Implement file-event ingestion and dispatcher routing**

Handle `GenLSP.Notifications.WorkspaceDidChangeWatchedFiles` in `Dispatcher`. Use `FileEvents` for both LSP events and normalized file-system events. Keep processing per event URI only; do not scan the project.

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/file_events_test.exs apps/phoenix_ls/test/phoenix_ls/workspace/file_watcher_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/watched_files_transport_test.exs
```

Expected: PASS.

## Task 5: Full Verification And Commit

**Files:**
- All files changed by this plan.

- [x] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If it fails, run `mix format`, inspect the diff, and rerun the check.

- [x] **Step 2: Run complete Elixir server tests**

Run:

```bash
cd server && mix test
```

Expected: PASS.

- [x] **Step 3: Compile with warnings as errors**

Run:

```bash
cd server && mix compile --warnings-as-errors
```

Expected: PASS.

- [x] **Step 4: Check no semantic regex was introduced**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls server/apps/phoenix_ls/test/phoenix_ls --glob '!**/architecture/regex_policy_test.exs' || true
```

Expected: no output.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-lsp-runtime-indexing-infrastructure.md server/apps/phoenix_ls/mix.exs server/apps/phoenix_ls/lib/phoenix_ls/cli.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/runtime.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/request_context.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex server/apps/phoenix_ls/lib/phoenix_ls/index/invalidation.ex server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_events.ex server/apps/phoenix_ls/lib/phoenix_ls/workspace/file_watcher.ex server/apps/phoenix_ls/test/phoenix_ls/cli_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/dispatcher_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/invalidation_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs server/apps/phoenix_ls/test/phoenix_ls/workspace/file_events_test.exs server/apps/phoenix_ls/test/phoenix_ls/workspace/file_watcher_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/watched_files_transport_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
git commit -m "feat: add lsp runtime and async indexing"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers objective items 1, 2, 3, and 4. It also preserves the already-present Phoenix dependency detection from item 6, but does not claim item 6 complete beyond that existing behavior.
- Placeholder scan: No step uses TBD/TODO/fill-in implementation language.
- Type consistency: Module names are consistent across tasks: `Runtime`, `Dispatcher`, `RequestContext`, `Invalidation`, `Indexer`, `FileEvents`, and `FileWatcher`.
