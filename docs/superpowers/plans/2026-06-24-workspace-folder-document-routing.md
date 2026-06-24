# Workspace Folder Document Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support LSP workspace folders and route text document sync by each document URI.

**Architecture:** `PhoenixLS.LSP.WorkspaceFolders` owns workspace-folder initialization and `workspace/didChangeWorkspaceFolders` notification handling. `PhoenixLS.LSP.Server` remains the protocol dispatcher: it advertises workspace-folder support only after wiring the notification handler, assigns workspace-folder state during initialize, and delegates folder changes. `PhoenixLS.LSP.TextDocumentSync` resolves the target document store from the document URI via `Project.Manager.ensure_project_for_uri/2`, falling back to the session document store for files outside Mix projects.

**Tech Stack:** Elixir, OTP assigns, GenLSP 0.11.3, ExUnit.

---

## File Structure

- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
  - Advertise `workspace.workspaceFolders.supported: true`.
  - Advertise `workspace.workspaceFolders.changeNotifications: true`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/workspace_folders.ex`
  - Assign initial workspace folder state from `InitializeParams.workspace_folders`.
  - Ensure project engines for located workspace folder URIs.
  - Handle `workspace/didChangeWorkspaceFolders` add/remove notifications.
  - Keep state in LSP assigns as:
    - `workspace_folders`: `%{folder_uri => folder_name}`
    - `workspace_project_roots`: `MapSet` of located Mix project root URIs
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Add default workspace folder assigns in `init/2`.
  - Read `workspace_folders` in initialize params.
  - Use the first workspace folder as a project routing fallback when `root_uri` is nil.
  - Handle `WorkspaceDidChangeWorkspaceFolders` notification.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
  - Resolve the document store from the document URI for open/change/close.
  - Fall back to `LSP.assigns(lsp).document_store` when no Mix project owns the document URI.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`
  - Assert workspace folder support is advertised.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/workspace_folders_test.exs`
  - Cover initial workspace-folder assignment and change notifications.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
  - Assert default workspace folder assigns.
  - Assert initialize with workspace folders tracks folders and project roots.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`
  - Cover document URI routing into a project-local document store even when the session fallback store is different.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`
  - Cover a document opened from a different Mix project than the initialized root.

## Task 1: Workspace Folder Capability

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`

- [x] **Step 1: Write failing capability test**

Add assertions:

```elixir
assert capabilities.workspace.workspace_folders.supported == true
assert capabilities.workspace.workspace_folders.change_notifications == true
```

- [x] **Step 2: Run capability test and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs
```

Expected: FAIL because `Capabilities.build/0` does not advertise workspace folders.

- [x] **Step 3: Implement workspace folder capability**

Set:

```elixir
workspace: %{
  workspace_folders: %WorkspaceFoldersServerCapabilities{
    supported: true,
    change_notifications: true
  }
}
```

- [x] **Step 4: Run capability test and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs
```

Expected: PASS.

## Task 2: Workspace Folder State And Notifications

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/workspace_folders.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/workspace_folders_test.exs`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`

- [x] **Step 1: Write failing workspace folder tests**

Create tests that:
- build Mix project fixtures
- call `WorkspaceFolders.assign_initial/2`
- assert `workspace_folders` maps folder URI to name
- assert `workspace_project_roots` contains the located Mix project root URI
- send `WorkspaceDidChangeWorkspaceFolders` with added/removed folders and assert the assigns are updated

Update server lifecycle tests to assert init defaults:

```elixir
assert LSP.assigns(initialized_lsp).workspace_folders == %{}
assert LSP.assigns(initialized_lsp).workspace_project_roots == MapSet.new()
```

- [x] **Step 2: Run workspace folder tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/workspace_folders_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: FAIL because `WorkspaceFolders` does not exist and server assigns are missing.

- [x] **Step 3: Implement workspace folder module and server notification delegation**

Add `PhoenixLS.LSP.WorkspaceFolders` with:
- `assign_initial(lsp, folders)`
- `handle(%WorkspaceDidChangeWorkspaceFolders{}, lsp)`
- folder normalization for GenLSP structs and decoded maps
- project root ensuring via `Project.Manager.ensure_project_for_uri/2`

Update `Server.init/2` assigns and initialize handling:

```elixir
lsp = WorkspaceFolders.assign_initial(lsp, workspace_folders)
project_uri = root_uri || WorkspaceFolders.first_uri(workspace_folders)
lsp = assign_project(lsp, project_uri)
```

Add notification delegation for `%WorkspaceDidChangeWorkspaceFolders{}`.

- [x] **Step 4: Run workspace folder tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/workspace_folders_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: PASS.

## Task 3: Document Sync Routes By Document URI

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`

- [x] **Step 1: Write failing document routing tests**

Add callback and transport tests asserting:
- session initialized/fallback store can be project A or fallback
- opened document URI inside project B is stored in project B's document store
- fallback store does not receive project B document

- [x] **Step 2: Run document routing tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
```

Expected: FAIL because `TextDocumentSync` still uses a static session document store.

- [x] **Step 3: Implement document URI routing**

In `TextDocumentSync`, replace static `document_store(lsp)` calls with `document_store(lsp, uri)`:

```elixir
case Manager.ensure_project_for_uri(project_manager, uri) do
  {:ok, engine} -> engine.document_store
  _ -> fallback_document_store(lsp)
end
```

- [x] **Step 4: Run document routing tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
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
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls/lsp server/apps/phoenix_ls/test/phoenix_ls/lsp || true
```

Expected: no output.

- [x] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-workspace-folder-document-routing.md server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/workspace_folders.ex server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/workspace_folders_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
git commit -m "feat: route documents by workspace project"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers workspace folder capability, initialize workspace-folder state, workspace folder change notifications, and per-document URI routing. It intentionally does not implement file watchers, workspace folder removal engine shutdown, indexing, diagnostics, completion, or dynamic registration.
- Placeholder scan: No task uses TBD, TODO, or unspecified tests.
- Type consistency: The plan consistently uses `WorkspaceFolders.assign_initial/2`, `WorkspaceFolders.handle/2`, `WorkspaceFolders.first_uri/1`, `workspace_folders`, `workspace_project_roots`, and `Manager.ensure_project_for_uri/2`.
