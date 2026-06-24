# HEEx Cursor Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small HEEx cursor context classifier so future completions can distinguish tag, attribute, value, expression, and text positions.

**Architecture:** `PhoenixLS.HEEx.CursorContext` is a pure module that receives source text and an LSP position, delegates UTF-16 position conversion to `PhoenixLS.Support.Positions`, and runs a no-regex lexical state machine over the source before the cursor. This is not a full HEEx parser; it is a narrowly scoped cursor classifier that can be replaced or strengthened when a stable HEEx parser/tokenizer boundary is added.

**Tech Stack:** Elixir, GenLSP position/range structs, existing UTF-16 position utilities, ExUnit.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/heex/cursor_context.ex`
  - Return `%PhoenixLS.HEEx.CursorContext{}` for cursor context.
  - Support context kinds `:text`, `:tag_name`, `:attribute_name`, `:attribute_value`, and `:expression`.
  - Track current tag name, attribute name, prefix, and closing-tag status.
  - Use `PhoenixLS.Support.Positions.lsp_position_to_offset/2`.
  - Avoid regex.
- Create `server/apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs`
  - Cover tag name, component tag name, slot tag name, attribute name, quoted value, expression, text, closing tag, invalid position, and UTF-16 positions.

## Task 1: Cursor Context Classifier

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/heex/cursor_context.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs`

- [x] **Step 1: Write failing cursor context tests**

Add marker-based tests using `|` as the cursor marker. Convert the marker byte offset to an LSP position via `PhoenixLS.Support.Positions.offset_to_lsp_position/2` so tests exercise the same UTF-16 path as LSP requests.

- [x] **Step 2: Run cursor context tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs
```

Expected: FAIL because `PhoenixLS.HEEx.CursorContext` does not exist.

- [x] **Step 3: Implement cursor context classifier**

Implement `PhoenixLS.HEEx.CursorContext.at/2` with a small lexical state machine:
- `:text` when outside tags and expressions
- `:tag_name` after `<`, `</`, `<.`, `<:`, or component aliases before whitespace or `>`
- `:attribute_name` after whitespace inside a tag, including partial prefixes
- `:attribute_value` after `=` and inside quoted/unquoted attribute values
- `:expression` inside `{...}` in text or attribute expression values

- [x] **Step 4: Run cursor context tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs
```

Expected: PASS.

## Task 2: Full Verification And Commit

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

Expected: no output.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-heex-cursor-context.md server/apps/phoenix_ls/lib/phoenix_ls/heex/cursor_context.ex server/apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs
git commit -m "feat: classify heex cursor context"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers the first cursor context boundary needed before component completions, without adding unstable LiveView internals or semantic regex parsing.
- Placeholder scan: No task uses TODO, TBD, or unspecified implementation text.
- Type consistency: The plan consistently uses `PhoenixLS.HEEx.CursorContext.at/2`, context `kind`, `tag`, `attribute`, `prefix`, and `closing?`.
