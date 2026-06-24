# Index Store Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an engine-owned ETS-backed index store for project facts with mandatory source location and provenance.

**Architecture:** `PhoenixLS.Index.Fact` defines the minimal fact shape shared by future Phoenix extractors. `PhoenixLS.Index.Store` owns an ETS table behind a GenServer API and provides explicit invalidation by URI. `PhoenixLS.Project.Engine` supervises one index store per project root and exposes it in the engine handle.

**Tech Stack:** Elixir, OTP GenServer/Supervisor, ETS, ExUnit.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/fact.ex`
  - Define the indexed fact struct.
  - Require `kind`, `id`, `uri`, `range`, and `provenance`.
  - Keep feature-specific values in `data`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/store.ex`
  - Own an ETS table inside a GenServer.
  - Support `put/2`, `all/1`, `by_uri/2`, `by_kind/2`, `delete_uri/2`, and `clear/1`.
  - Replace facts by `{kind, uri, id}`.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
  - Add `index_store(root_uri)`.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
  - Supervise the project index store next to the document store.
  - Add `index_store` to the engine handle.
- Create `server/apps/phoenix_ls/test/phoenix_ls/index/fact_test.exs`
  - Cover required location/provenance construction.
- Create `server/apps/phoenix_ls/test/phoenix_ls/index/store_test.exs`
  - Cover insert, replacement, query, and URI invalidation.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`
  - Assert the engine starts and exposes the project index store.

## Task 1: Index Fact Shape

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/fact.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/index/fact_test.exs`

- [x] **Step 1: Write failing fact tests**

Create tests asserting `Fact.new!/1` builds a fact with mandatory fields and raises when `range` or `provenance` is missing.

- [x] **Step 2: Run fact tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/fact_test.exs
```

Expected: FAIL because `PhoenixLS.Index.Fact` does not exist.

- [x] **Step 3: Implement `PhoenixLS.Index.Fact`**

Create a focused struct with `new!/1`, required field validation, and `key/1`.

- [x] **Step 4: Run fact tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/fact_test.exs
```

Expected: PASS.

## Task 2: ETS Index Store

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/store.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/index/store_test.exs`

- [x] **Step 1: Write failing store tests**

Create tests asserting the store:
- stores and returns facts
- filters by URI
- filters by kind
- replaces a fact with the same key
- deletes all facts for one URI without deleting other URIs
- clears the table

- [x] **Step 2: Run store tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/store_test.exs
```

Expected: FAIL because `PhoenixLS.Index.Store` does not exist.

- [x] **Step 3: Implement `PhoenixLS.Index.Store`**

Use a GenServer-owned ETS table and expose only explicit API functions.

- [x] **Step 4: Run store tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/store_test.exs
```

Expected: PASS.

## Task 3: Engine-Owned Index Store

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`

- [x] **Step 1: Write failing engine test**

Extend engine tests to assert `Names.index_store(root_uri)` exists, accepts index facts, and is exposed on `Engine.handle/2`.

- [x] **Step 2: Run engine tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs
```

Expected: FAIL because the engine does not supervise or expose an index store.

- [x] **Step 3: Wire index store into project engines**

Add `Names.index_store/1`, include `Index.Store` in `Engine.init/1`, and add `index_store` to `Engine.t`.

- [x] **Step 4: Run engine tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs
```

Expected: PASS.

## Task 4: Full Verification And Commit

**Files:**
- All changed files in this plan.

- [x] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If it fails, run `mix format`, inspect the diff, and rerun.

- [x] **Step 2: Run complete test suite**

Run:

```bash
cd server && mix test
```

Expected: PASS.

- [x] **Step 3: Run warnings-as-errors compile**

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

Expected: no output. The architecture policy test is excluded because it intentionally contains the forbidden token list.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-index-store-foundation.md server/apps/phoenix_ls/lib/phoenix_ls/index/fact.ex server/apps/phoenix_ls/lib/phoenix_ls/index/store.ex server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex server/apps/phoenix_ls/test/phoenix_ls/index/fact_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/store_test.exs server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs
git commit -m "feat: add project index store foundation"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan adds the reusable fact shape, ETS-backed store, explicit invalidation path, and engine ownership needed before Phoenix semantic extractors.
- Placeholder scan: No step uses TODO, TBD, or unspecified implementation text.
- Type consistency: The plan consistently uses `PhoenixLS.Index.Fact`, `PhoenixLS.Index.Store`, `Names.index_store/1`, and `Engine.index_store`.
