# Component Completion Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure component completion provider that converts indexed component facts and HEEx cursor context into LSP completion items.

**Architecture:** `PhoenixLS.Features.Completion.Components` receives a `%PhoenixLS.HEEx.CursorContext{}` and already-indexed `PhoenixLS.Index.Fact` values. It returns `GenLSP.Structures.CompletionItem` structs for function component tags, component attributes, slot tags, and slot attributes. This plan intentionally does not advertise completion capability or handle `textDocument/completion`; protocol wiring will be a later slice.

**Tech Stack:** Elixir, ExUnit, `GenLSP.Structures.CompletionItem`, `PhoenixLS.HEEx.CursorContext`, existing component index facts.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/components.ex`
  - Expose `complete/2`.
  - Return function component tag completions in HEEx component tag-name contexts.
  - Return component attr completions in function component attribute-name contexts.
  - Return slot tag completions in HEEx slot tag-name contexts.
  - Return slot attr completions in slot attribute-name contexts.
  - Avoid regex and source parsing; consume cursor context and facts only.
- Create `server/apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs`
  - Build facts through `PhoenixLS.Index.ElixirSource.facts/3`.
  - Build contexts through `PhoenixLS.HEEx.CursorContext.at/2`.
  - Assert completion item labels, kinds, details, insert text, and data.

## Task 1: Test Component Completion Provider

**Files:**
- Create: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs`

- [x] **Step 1: Write failing tests**

Add tests that assert:
- `<.bu| />` returns a `.button` function component completion and does not return `.card`.
- `<.button |>` returns `label` and `kind` component attribute completions.
- `<:in| />` returns an `:inner_block` slot tag completion.
- `<:inner_block |>` returns a `class` slot attribute completion.
- text, expression, and closing-tag contexts return no component completions.

- [x] **Step 2: Run focused completion tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs
```

Expected: FAIL because `PhoenixLS.Features.Completion.Components` does not exist yet.

## Task 2: Implement Pure Completion Items

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/components.ex`

- [x] **Step 1: Implement `complete/2` dispatch**

Return completions only for these cursor contexts:
- `:tag_name` with a non-closing prefix beginning with `.` for function components
- `:tag_name` with a non-closing prefix beginning with `:` for slots
- `:attribute_name` inside a tag beginning with `.` for component attrs
- `:attribute_name` inside a tag beginning with `:` for slot attrs

- [x] **Step 2: Build `CompletionItem` structs**

Use these item shapes:
- component tag: label `.button`, kind `CompletionItemKind.function()`, detail `AppWeb.CoreComponents.button/1`, insert text `.button`
- component attr: label `label`, kind `CompletionItemKind.property()`, detail `attr :label, :string`, insert text `label`
- slot tag: label `:inner_block`, kind `CompletionItemKind.field()`, detail `slot :inner_block`, insert text `:inner_block`
- slot attr: label `class`, kind `CompletionItemKind.property()`, detail `slot attr :class, :string`, insert text `class`

Use `InsertTextFormat.plain_text()` and JSON-safe string-keyed `data` maps.

- [x] **Step 3: Run focused completion tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs
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
git add docs/superpowers/plans/2026-06-24-component-completion-provider.md server/apps/phoenix_ls/lib/phoenix_ls/features/completion/components.ex server/apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs
git commit -m "feat: add component completion provider"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers pure component, attribute, slot, and slot-attribute completion item generation from existing v2 facts. It intentionally excludes LSP request handling and capability advertisement.
- Placeholder scan: No task uses TBD, TODO, or unspecified implementation text.
- Type consistency: The plan consistently uses `PhoenixLS.Features.Completion.Components.complete/2` and `GenLSP.Structures.CompletionItem`.
