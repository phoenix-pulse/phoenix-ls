# LSP Component Completion Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the pure component completion provider into `textDocument/completion` and advertise completion capability.

**Architecture:** Add a small `PhoenixLS.LSP.Completion` request boundary. It fetches the open document from the already-known project document store, classifies cursor context with `PhoenixLS.HEEx.CursorContext`, reads warm index facts from the already-known project index store, and delegates item generation to `PhoenixLS.Features.Completion.Components`. Request routing must not locate projects or scan the filesystem; it uses `project_root_uri` and `workspace_project_roots` already assigned during initialization.

**Tech Stack:** Elixir, ExUnit, GenLSP request/transport tests, existing document/index stores, existing component completion provider.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
  - Expose `handle/2` for `GenLSP.Requests.TextDocumentCompletion`.
  - Resolve the project engine from already-known LSP assigns.
  - Return `[]` for unsupported contexts, missing documents, missing project stores, invalid positions, or missing indexes.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Route `%GenLSP.Requests.TextDocumentCompletion{}` to `PhoenixLS.LSP.Completion.handle/2`.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
  - Advertise `completion_provider` only now that the handler exists.
  - Use trigger characters `"."` and `":"`; no resolve provider yet.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs`
  - Index a component document through `didOpen`.
  - Open a HEEx document in the same project.
  - Send `textDocument/completion` and assert component tag completions.
  - Assert unsupported/missing contexts return an empty list.
- Modify existing capability/lifecycle transport tests for the new advertised completion capability.

## Task 1: Failing Capability And Transport Tests

**Files:**
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`

- [x] **Step 1: Update capability tests**

Assert `Capabilities.build().completion_provider` is a `GenLSP.Structures.CompletionOptions` with:
- `trigger_characters == [".", ":"]`
- `resolve_provider == false`

Keep hover and definition provider assertions at `nil`.

- [x] **Step 2: Add failing completion transport tests**

Add tests that:
- initialize a fixture Mix project
- open `lib/app_web/components/core_components.ex` as Elixir source containing a `button/1` component
- open `lib/app_web/live/page.html.heex` with `<.bu| />`
- send `textDocument/completion`
- assert the result includes `.button`

Also assert text context completion returns `[]`.

- [x] **Step 3: Run focused LSP tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: FAIL because completion capability and request handling are not implemented yet.

## Task 2: Implement LSP Completion Routing

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`

- [x] **Step 1: Advertise completion capability**

Set `completion_provider` to `%GenLSP.Structures.CompletionOptions{trigger_characters: [".", ":"], resolve_provider: false}`.

- [x] **Step 2: Route completion requests from the server**

Alias `TextDocumentCompletion` in `PhoenixLS.LSP.Server` and add a `handle_request/2` clause that delegates to `PhoenixLS.LSP.Completion.handle/2`.

- [x] **Step 3: Implement the completion request boundary**

In `PhoenixLS.LSP.Completion.handle/2`:
- read `uri` and `position` from request params
- find the matching known project root from `project_root_uri` and `workspace_project_roots`
- fetch the existing engine with `Manager.fetch_engine/2`
- fetch the open document with `DocumentStore.fetch/2`
- classify context with `CursorContext.at/2`
- read facts with `IndexStore.all/1`
- call `PhoenixLS.Features.Completion.Components.complete/2`
- reply with the returned item list, or `[]` on any missing/invalid state

- [x] **Step 4: Run focused LSP tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
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
git add docs/superpowers/plans/2026-06-24-lsp-component-completion-wiring.md server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
git commit -m "feat: wire component completions into lsp"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers capability advertisement and `textDocument/completion` routing for existing component facts. It intentionally does not implement completion resolve, generic Elixir completions, hover, definition, or diagnostics.
- Placeholder scan: No task uses TBD, TODO, or unspecified implementation text.
- Type consistency: The plan consistently uses `PhoenixLS.LSP.Completion.handle/2`, `GenLSP.Requests.TextDocumentCompletion`, and `GenLSP.Structures.CompletionOptions`.
