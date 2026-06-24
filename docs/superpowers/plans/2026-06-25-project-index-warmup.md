# Project Index Warmup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Index source-backed Phoenix facts from disk when a project engine starts, so completion, hover, definition, diagnostics, and explorer requests are not limited to files the editor has opened.

**Architecture:** Keep scanning and indexing inside the project engine boundary by extending `PhoenixLS.Index.Indexer`. Add a small pure `PhoenixLS.Index.ProjectScan` helper that enumerates supported source files from a project root URI. Engine startup passes its root URI to the indexer; the indexer performs a source-only warmup job without compiling or executing project code.

**Tech Stack:** Elixir, ExUnit, OTP GenServer, existing `PhoenixLS.Index.DocumentIndexer`, existing URI helpers.

---

### Task 1: Source File Scan Helper

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/project_scan.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/project_scan_test.exs`

- [x] **Step 1: Write failing scan tests**

Cover sorted URI enumeration for `lib/**/*.ex` and `lib/**/*.heex`, ignore unsupported files, ignore `_build` and `deps` by construction, and return `{:error, :not_file_uri}` for non-file roots.

- [x] **Step 2: Verify scan tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/project_scan_test.exs`

- [x] **Step 3: Implement `PhoenixLS.Index.ProjectScan.uris/1`**

Use `PhoenixLS.Support.URI.file_uri_to_path/1`, `Path.wildcard/1`, `Path.join/1`, `Enum.sort/1`, and `PhoenixLS.Support.URI.path_to_file_uri!/1`. Enumerate only `lib/**/*.ex` and `lib/**/*.heex`.

- [x] **Step 4: Verify scan tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/project_scan_test.exs`

### Task 2: Indexer Project Warmup Job

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 1: Write failing indexer warmup tests**

Cover `Indexer.schedule_project/2` indexing both `.ex` and `.heex` files from disk into the store, and emitting `[:phoenix_ls, :indexer, :project]` telemetry.

- [x] **Step 2: Verify indexer warmup tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

- [x] **Step 3: Implement project job**

Add `schedule_project/2`, `handle_cast({:index_project, root_uri}, state)`, and `handle_continue({:index_project, root_uri}, state)`. Reuse `DocumentIndexer.index/2` by reading each scanned file into a `%PhoenixLS.Workspace.Document{}` with language ID `"elixir"` for `.ex` and `"phoenix-heex"` for `.heex`.

- [x] **Step 4: Verify indexer warmup tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs`

### Task 3: Engine Startup Warmup

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`

- [x] **Step 1: Write failing engine warmup test**

Create a temporary Mix project with `lib/app_web/components/core_components.ex` and `lib/app_web/controllers/page_html/index.html.heex`, start an engine for its root URI, and assert the named index store eventually contains component and template facts.

- [x] **Step 2: Verify engine warmup test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`

- [x] **Step 3: Pass `root_uri` to the indexer child**

Modify the engine child spec so `{Indexer, name: indexer, index_store: index_store, root_uri: root_uri}` starts the indexer with enough context to schedule a startup warmup.

- [x] **Step 4: Verify engine warmup test passes**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`

### Task 4: Template Range Serialization Fix

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 1: Strengthen template range test**

Assert template fact ranges use `%GenLSP.Structures.Position{}` for `start` and `end`, matching outbound LSP serialization requirements.

- [x] **Step 2: Verify test fails if ranges are maps**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 3: Emit struct positions from template facts**

Construct `%GenLSP.Structures.Position{}` for the start and converted end position in `PhoenixLS.Introspection.Template`.

- [x] **Step 4: Verify document indexer tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

### Task 5: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
