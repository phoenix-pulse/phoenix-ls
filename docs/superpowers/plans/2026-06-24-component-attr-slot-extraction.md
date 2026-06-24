# Component Attribute And Slot Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit source-backed index facts for Phoenix component `attr` and `slot` declarations in open Elixir documents.

**Architecture:** `PhoenixLS.Introspection.Component` will remain the component-specific extraction boundary. `PhoenixLS.Index.ElixirSource` will pass module body expressions into that module, where top-level `attr` and `slot` declarations are accumulated until the next public arity-1 HEEx function component. Attribute and slot facts are separate index facts so each declaration keeps its own source range and provenance.

**Tech Stack:** Elixir, ExUnit, `Code.string_to_quoted/2`, existing `PhoenixLS.Index.Fact` structs.

---

## File Structure

- Modify `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
  - Add `facts_for_module_body/4`.
  - Preserve `function_component_fact/8` for direct single-function classification.
  - Emit `:component_attr`, `:component_slot`, and nested slot `:component_slot_attr` facts.
  - Avoid regex and project-code execution.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
  - Delegate module-body component extraction to the component introspection module.
  - Stop direct per-function component extraction in this module to avoid duplicated component facts.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
  - Add parser-level tests for component attr, slot, and slot attr facts.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`
  - Add integration coverage that open document indexing stores component metadata facts.

## Task 1: Test Attribute And Slot Extraction

**Files:**
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 1: Write failing parser-level tests**

Add a test fixture with:

```elixir
defmodule AppWeb.CoreComponents do
  attr :label, :string, required: true
  attr :kind, :atom, default: :primary, values: [:primary, :secondary]

  slot :inner_block, required: true do
    attr :class, :string
  end

  def button(assigns) do
    ~H\"\"\"
    <button><%= render_slot(@inner_block) %></button>
    \"\"\"
  end
end
```

Assert that `ElixirSource.facts/3` emits:
- two `:component_attr` facts owned by `AppWeb.CoreComponents.button/1`
- one `:component_slot` fact owned by `AppWeb.CoreComponents.button/1`
- one `:component_slot_attr` fact owned by slot `inner_block`
- declaration source ranges and provenance on each fact

- [x] **Step 2: Write failing document-indexer integration test**

Add a test that indexes the same shape through `DocumentIndexer.index/2` and asserts `Store.by_kind/2` returns the attr and slot facts.

- [x] **Step 3: Run the focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: FAIL because `:component_attr`, `:component_slot`, and `:component_slot_attr` facts are not produced yet.

## Task 2: Implement Module-Body Component Metadata Extraction

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`

- [x] **Step 1: Add module body delegation**

Change `ElixirSource.collect/4` for `defmodule` bodies so ordinary nested module/function facts still come from the existing traversal and component metadata facts come from `Component.facts_for_module_body/4`.

- [x] **Step 2: Implement declaration accumulation**

In `PhoenixLS.Introspection.Component`, walk top-level module expressions in order:
- collect `attr` declarations into a pending list
- collect `slot` declarations into a pending list
- when a public arity-1 HEEx component function appears, emit the component fact plus pending attr/slot facts for that component
- clear pending declarations after assigning them to a component
- ignore private functions and non-component functions

- [x] **Step 3: Emit fact shapes**

Use these fact kinds and ids:
- component attr id: `"AppWeb.CoreComponents.button/1:attr:label"`
- component slot id: `"AppWeb.CoreComponents.button/1:slot:inner_block"`
- slot attr id: `"AppWeb.CoreComponents.button/1:slot:inner_block:attr:class"`

Use data maps containing component module/name/id, declaration name/type/options, and slot ownership where applicable.

- [x] **Step 4: Run focused tests and verify GREEN**

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
git add docs/superpowers/plans/2026-06-24-component-attr-slot-extraction.md server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
git commit -m "feat: extract component attrs and slots"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers component attribute, slot, and slot-attribute extraction from open Elixir documents and leaves completion providers to the next slice.
- Placeholder scan: No task uses TBD, TODO, or unspecified implementation text.
- Type consistency: The plan consistently uses `:component_attr`, `:component_slot`, and `:component_slot_attr` fact kinds with `PhoenixLS.Index.Fact`.
