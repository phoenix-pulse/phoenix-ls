# Project Hardening Fixtures Source Map Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit source-only engine status/restart behavior, reusable Phoenix fixture apps, source-map utilities, and PhoenixLS telemetry events.

**Architecture:** Keep manager-owned state stable and source-only by default. Add small focused modules: `Project.EngineStatus`, `Parsing.SourceMap`, and `Support.Telemetry`. Fixtures live under `server/apps/phoenix_ls/test/fixtures/` and are treated as static source projects for tests, not compiled applications.

**Tech Stack:** Elixir, ExUnit, OTP DynamicSupervisor, `:telemetry`, existing URI/position helpers.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/project/engine_status.ex`
  - Source-only running/missing/degraded status struct.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
  - Add `status/2` and `restart_engine/2`.
  - Keep engine restarts explicit and observable without loading project code.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/parsing/source_map.ex`
  - Convert embedded offsets to source LSP positions/ranges.
  - Convert Elixir parser metadata to LSP ranges and reject generated metadata explicitly.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/support/telemetry.ex`
  - Small wrapper around `:telemetry.execute/3` and `:telemetry.span/3`.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/index/indexer.ex`
  - Emit telemetry for document, URI, and delete indexing jobs.
- Create static fixture apps under:
  - `server/apps/phoenix_ls/test/fixtures/phoenix_1_7_app/`
  - `server/apps/phoenix_ls/test/fixtures/phoenix_1_8_app/`
  - `server/apps/phoenix_ls/test/fixtures/liveview_components_app/`
  - `server/apps/phoenix_ls/test/fixtures/umbrella_app/`
  - `server/apps/phoenix_ls/test/fixtures/broken_syntax_app/`
  - `server/apps/phoenix_ls/test/fixtures/non_compiling_app/`

## Task 1: Engine Status And Restart Hardening

- [x] **Step 1: Write failing tests**

Add `server/apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs` and extend manager tests to assert:
- `Manager.status/2` returns `:missing` for unknown roots.
- Ensured engines report `:running`, `source_only?: true`, and stable process names.
- Killing an engine process is contained by the dynamic supervisor and `Manager.fetch_engine/2` returns a restarted engine.
- `Manager.restart_engine/2` explicitly replaces an engine.

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs
```

Expected: FAIL because `EngineStatus`, `Manager.status/2`, and `Manager.restart_engine/2` are missing.

- [x] **Step 3: Implement status and restart APIs**

Create `EngineStatus` and add manager calls for `status` and `restart_engine`. The status must describe source-only mode without compiling or executing project code.

- [x] **Step 4: Run tests and verify GREEN**

Run the same focused command. Expected: PASS.

## Task 2: Fixture Apps

- [x] **Step 1: Write failing fixture tests**

Add `server/apps/phoenix_ls/test/phoenix_ls/fixtures_test.exs` to assert every required fixture directory exists with a `mix.exs`, representative Phoenix source files, broken syntax sample, non-compiling sample, and umbrella child app.

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/fixtures_test.exs
```

Expected: FAIL because fixture directories do not exist.

- [x] **Step 3: Add static fixture projects**

Create the fixture source trees with realistic Phoenix modules, router files, LiveView modules, components, schemas, templates, an umbrella child app, one intentionally broken syntax file, and one syntactically valid non-compiling file.

- [x] **Step 4: Run fixture tests and verify GREEN**

Run the same fixture test command. Expected: PASS.

## Task 3: Source Map Utilities

- [x] **Step 1: Write failing source map tests**

Add `server/apps/phoenix_ls/test/phoenix_ls/parsing/source_map_test.exs` to assert:
- embedded HEEx offsets inside a `~H` body map back to outer source LSP positions
- CRLF and Unicode UTF-16 positions are preserved through `PhoenixLS.Support.Positions`
- metadata ranges convert to LSP ranges
- generated metadata returns `{:error, :generated}`

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/parsing/source_map_test.exs
```

Expected: FAIL because `PhoenixLS.Parsing.SourceMap` does not exist.

- [x] **Step 3: Implement source map utilities**

Create `SourceMap` with `new/2`, `to_source_offset/2`, `to_lsp_position/2`, `to_lsp_range/3`, and `range_from_meta/2`.

- [x] **Step 4: Run source map tests and verify GREEN**

Run the same focused command. Expected: PASS.

## Task 4: Telemetry Events

- [x] **Step 1: Write failing telemetry tests**

Add `server/apps/phoenix_ls/test/phoenix_ls/support/telemetry_test.exs` and extend indexer tests to assert:
- `PhoenixLS.Support.Telemetry.execute/3` emits PhoenixLS-prefixed events.
- `Indexer` emits job events for document indexing, disk URI indexing, and delete/invalidation jobs.

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/support/telemetry_test.exs apps/phoenix_ls/test/phoenix_ls/index/indexer_test.exs
```

Expected: FAIL because telemetry wrapper/events are missing.

- [x] **Step 3: Implement telemetry wrapper and indexer events**

Use `:telemetry.execute/3` with event names under `[:phoenix_ls, ...]`. Do not add noisy logs in hot paths; telemetry is the observable surface for now.

- [x] **Step 4: Run telemetry tests and verify GREEN**

Run the same focused command. Expected: PASS.

## Task 5: Verification And Commit

- [x] **Step 1: Format check**

Run `cd server && mix format --check-formatted`.

- [x] **Step 2: Full test suite**

Run `cd server && mix test`.

- [x] **Step 3: Warnings-as-errors compile**

Run `cd server && mix compile --warnings-as-errors`.

- [x] **Step 4: Regex policy scan**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls server/apps/phoenix_ls/test/phoenix_ls --glob '!**/architecture/regex_policy_test.exs' || true
```

Expected: no output.

- [x] **Step 5: Commit**

Commit message:

```bash
git commit -m "feat: add project hardening fixtures and telemetry"
```

## Self-Review

- Spec coverage: Covers objective items 5, 7, 8, and 9; item 6 already has Phoenix dependency detection and remains available through locator tests.
- Placeholder scan: No TBD/TODO/fill-in steps.
- Type consistency: Module and function names are consistent across tests and implementation.
