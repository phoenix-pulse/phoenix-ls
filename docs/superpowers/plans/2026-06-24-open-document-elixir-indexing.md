# Open Document Elixir Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Index open `.ex` editor documents into the project index store with module and function facts.

**Architecture:** `PhoenixLS.Index.ElixirSource` is a pure extractor that turns `Code.string_to_quoted/2` AST metadata into `PhoenixLS.Index.Fact` values. `PhoenixLS.Index.DocumentIndexer` owns document-level indexing policy: skip non-Elixir documents, clear stale URI facts before indexing, and clear stale facts on parse failure. `PhoenixLS.LSP.TextDocumentSync` remains protocol handling and delegates indexing after open/change/close using the project engine chosen for the document URI.

**Tech Stack:** Elixir AST via `Code.string_to_quoted/2`, GenLSP range structs, ETS-backed index store, ExUnit.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
  - Parse Elixir source using `Code.string_to_quoted/2`.
  - Extract `:module` facts from `defmodule`.
  - Extract `:function` facts from `def` and `defp`.
  - Build source ranges from AST metadata.
  - Return parse errors without raising.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/index/document_indexer.ex`
  - Index `PhoenixLS.Workspace.Document` values into a `PhoenixLS.Index.Store`.
  - Delete stale URI facts before successful reindexing.
  - Delete stale URI facts on Elixir parse failure.
  - Delete URI facts on close.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
  - Index open Elixir documents after document store open.
  - Reindex changed Elixir documents after full-document replacement.
  - Delete indexed facts for a closed document URI.
- Create `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
  - Cover module/function fact extraction, location/provenance, private functions, and parse errors.
- Create `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`
  - Cover open/change indexing policy and parse-error stale fact clearing.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`
  - Cover LSP open/change/close indexing through project engine routing.

## Task 1: Elixir Source Fact Extraction

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`

- [x] **Step 1: Write failing extractor tests**

Add tests for:
- module fact id and range
- public and private function facts
- provenance includes `source: :elixir_ast`
- invalid source returns `{:error, {:parse_error, _reason}}`

- [x] **Step 2: Run extractor tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs
```

Expected: FAIL because `PhoenixLS.Index.ElixirSource` does not exist.

- [x] **Step 3: Implement extractor**

Use `Code.string_to_quoted(source, columns: true, token_metadata: true)` and AST metadata only. Do not use regex or execute project code.

- [x] **Step 4: Run extractor tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs
```

Expected: PASS.

## Task 2: Document Indexer

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/index/document_indexer.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 1: Write failing document indexer tests**

Add tests for:
- Elixir documents store module/function facts.
- Reindexing a URI replaces stale facts.
- Parse failures clear stale facts and return `{:error, {:parse_error, _reason}}`.
- Non-Elixir documents return `:ignored` and do not add facts.
- Closing a URI deletes indexed facts for that URI.

- [x] **Step 2: Run document indexer tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: FAIL because `PhoenixLS.Index.DocumentIndexer` does not exist.

- [x] **Step 3: Implement document indexer**

Add `index/2` and `delete_uri/2`. Use `PhoenixLS.Index.Store.delete_uri/2` as the invalidation path.

- [x] **Step 4: Run document indexer tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: PASS.

## Task 3: LSP Text Document Sync Indexing

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`

- [x] **Step 1: Write failing LSP sync indexing tests**

Add tests proving:
- opening an Elixir document inside a Mix project writes facts into that project engine index store
- changing an Elixir document replaces stale facts
- closing an Elixir document deletes indexed facts

- [x] **Step 2: Run LSP sync indexing tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
```

Expected: FAIL because text document sync does not call the indexer.

- [x] **Step 3: Wire indexing into text document sync**

After open/change uses the document store, delegate to `DocumentIndexer.index/2` when a project engine exists. On close, call `DocumentIndexer.delete_uri/2`.

- [x] **Step 4: Run LSP sync indexing tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
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

Expected: no output.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-open-document-elixir-indexing.md server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex server/apps/phoenix_ls/lib/phoenix_ls/index/document_indexer.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs
git commit -m "feat: index open elixir documents"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan indexes open Elixir documents, introduces no regex parsing, stores source ranges/provenance, and connects indexing to LSP open/change/close.
- Placeholder scan: No task uses TODO, TBD, or unspecified implementation text.
- Type consistency: The plan consistently uses `PhoenixLS.Index.ElixirSource`, `PhoenixLS.Index.DocumentIndexer`, `PhoenixLS.Index.Store`, and `PhoenixLS.Index.Fact`.
