# Function Component Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit source-backed index facts for Phoenix function components defined in open Elixir documents.

**Architecture:** `PhoenixLS.Index.ElixirSource` keeps the single parse pass and delegates component-specific classification to a focused pure module. The first slice recognizes public arity-1 functions whose body contains a `~H` sigil and emits `:component` facts with the same source range and provenance conventions as module and function facts. Attribute and slot metadata stay out of scope for this plan.

**Tech Stack:** Elixir, ExUnit, `Code.string_to_quoted/2`, existing `PhoenixLS.Index.Fact` structs.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
  - Classify public arity-1 functions with HEEx bodies as function components.
  - Return `PhoenixLS.Index.Fact` structs with `kind: :component`.
  - Avoid regex and project-code execution.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
  - Delegate function-component classification after ordinary function fact extraction.
  - Preserve existing module and function fact ordering.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
  - Add parser-level component extraction tests.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`
  - Add integration coverage that open document indexing stores component facts.
- Create `server/config/config.exs`
  - Provide the Mix config file already referenced by the umbrella app config path.

## Task 1: Test Component Fact Extraction

**Files:**
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`
- Create: `server/config/config.exs`

- [x] **Step 1: Restore the required Mix config stub**

```elixir
import Config
```

- [x] **Step 2: Verify the existing focused index tests run**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: PASS for the current index suite.

- [x] **Step 3: Write failing component extraction tests**

Add tests that assert:
- `def button(assigns) do ~H"""...""" end` emits a `:component` fact.
- Private HEEx helpers do not emit component facts.
- Public arity-2 HEEx functions do not emit component facts.
- `DocumentIndexer.index/2` stores component facts alongside module and function facts.

- [x] **Step 4: Run the new tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: FAIL because no `:component` facts are produced yet.

## Task 2: Implement Minimal Component Extraction

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`

- [x] **Step 1: Create `PhoenixLS.Introspection.Component`**

Implement `function_component_fact/8` to return `{:ok, fact}` only when visibility is `:public`, arity is `1`, and the body AST contains `:sigil_H`.

- [x] **Step 2: Delegate from `PhoenixLS.Index.ElixirSource`**

After each ordinary function fact, ask the component module whether the same function should also emit a `:component` fact.

- [x] **Step 3: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: PASS.

## Task 3: Full Verification And Commit

**Files:**
- All files changed by this plan.

- [x] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If formatting fails, run `mix format`, inspect the diff, and rerun the check.

- [x] **Step 2: Run the complete Elixir server test suite**

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

Expected: no output.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-function-component-extraction.md server/config/config.exs server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
git commit -m "feat: extract function components"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers function component extraction from open Elixir documents and intentionally leaves attribute and slot extraction to the next rewrite slice.
- Placeholder scan: No task uses TBD, TODO, or unspecified implementation text.
- Type consistency: The plan consistently uses `kind: :component`, existing `PhoenixLS.Index.Fact` structs, and the existing `PhoenixLS.Index.ElixirSource.facts/3` entry point.
