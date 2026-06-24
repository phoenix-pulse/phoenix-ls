# HEEx Parser And Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a source-ranged HEEx document parser layer and use it for the first Phoenix diagnostics plus publish/clear notifications.

**Architecture:** Parse HEEx documents into small structs under `PhoenixLS.HEEx` with source ranges. Keep diagnostic rules pure under `PhoenixLS.Features.Diagnostics`, and keep LSP publish/clear behavior under `PhoenixLS.LSP.Diagnostics`. Do not parse Phoenix or HEEx semantics with regex.

**Tech Stack:** Elixir, ExUnit, `gen_lsp`, existing `PhoenixLS.Index.Fact`, existing UTF-16 conversion helper.

---

### Task 1: HEEx Document Parser

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/heex/document.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/heex/parser.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/heex/parser_test.exs`

- [x] **Step 1: Write failing parser tests**

Cover component tags, remote component tags, slot tags, attr names/values, self-closing tags, ignored closing tags, and ignored HEEx expression tags.

- [x] **Step 2: Verify parser tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/heex/parser_test.exs`

- [x] **Step 3: Implement parser structs and parser**

Return source-ranged tags and attrs. Track byte offsets internally and convert ranges with `PhoenixLS.Support.Positions`.

- [x] **Step 4: Verify parser tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/heex/parser_test.exs`

### Task 2: Pure Phoenix Diagnostics

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`

- [x] **Step 1: Write failing diagnostics tests**

Cover missing required attrs, unknown component attrs, unknown slots, invalid attr values, missing LiveComponent id/module, bad `phx-*` events, and unknown `~p` routes for the parser-supported cases.

- [x] **Step 2: Verify diagnostics tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`

- [x] **Step 3: Implement pure diagnostics**

Use parsed HEEx nodes plus indexed facts. Return `GenLSP.Structures.Diagnostic` values with stable codes, PhoenixLS source, warning/error severity, and source ranges from parsed nodes.

- [x] **Step 4: Verify diagnostics tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`

### Task 3: Diagnostics Publisher

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/diagnostics.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

- [x] **Step 1: Write failing publish/clear transport tests**

Assert diagnostics publish after open/change, debounce rapid changes, clear on close, and publish degraded/unavailable diagnostics when no project engine is available.

- [x] **Step 2: Wire publish/clear notifications**

After document changes, publish diagnostics for HEEx documents from the project index and current document text. On close, publish an empty diagnostic list.

- [x] **Step 3: Verify transport tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/diagnostics_transport_test.exs`

### Task 4: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run the semantic regex policy scan from the repo root
- [x] Commit the local slice after verification passes
