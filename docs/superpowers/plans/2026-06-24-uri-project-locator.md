# URI Project Locator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route file and root URIs to canonical Mix project roots without executing project code.

**Architecture:** `PhoenixLS.Support.URI` owns file URI/path conversion, keeping path encoding out of feature modules. `PhoenixLS.Project.Locator` walks the filesystem from a file or directory URI to find the nearest `mix.exs`, parses `mix.exs` with Elixir's parser only, and returns a structured project result with location/provenance data. `PhoenixLS.Project.Manager` uses the locator to canonicalize project engine keys, and `PhoenixLS.LSP.Server` initializes project routing through located Mix roots instead of treating the client `rootUri` as the project identity.

**Tech Stack:** Elixir, OTP GenServer, GenLSP, ExUnit, `URI`, `Code.string_to_quoted`.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/support/uri.ex`
  - Convert `file://` URIs to absolute paths.
  - Convert paths to encoded `file://` URIs.
  - Reject unsupported schemes without guessing.
- Create `server/apps/phoenix_ls/test/phoenix_ls/support/uri_test.exs`
  - Cover file URI decode, path URI encode, localhost file URIs, unsupported schemes, and path expansion.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/project/locator.ex`
  - Locate the nearest Mix project root for a file or directory URI.
  - Return root path, root URI, `mix.exs` path, Phoenix dependency flag, and optional umbrella root path/URI.
  - Parse `mix.exs` with AST APIs only; no regex.
- Create `server/apps/phoenix_ls/test/phoenix_ls/project/locator_test.exs`
  - Cover plain Mix projects, Phoenix dependency detection, nested file lookup, umbrella child lookup, missing project fallback, and unsupported URI schemes.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
  - Add `ensure_project_for_uri/2`.
  - Use located project root URI as the engine key.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`
  - Cover canonicalization from nested file URI to one project engine.
  - Cover missing projects returning `:error` without starting an engine.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Assign `:project_root_uri`.
  - On initialize, use `Manager.ensure_project_for_uri/2`; when it succeeds, use the project document store and project root URI.
  - Keep fallback document store when no Mix root is found.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
  - Cover located project root assignment from nested root URI.
  - Cover no-project root keeping fallback document store.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`
  - Create a Mix project fixture before initialize so the transport test verifies located project routing, not raw root URI routing.

## Task 1: URI Helpers

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/support/uri.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/support/uri_test.exs`

- [ ] **Step 1: Write failing URI tests**

Create tests asserting:

```elixir
assert SupportURI.file_uri_to_path("file:///tmp/hello%20world/lib/page.ex") ==
         {:ok, "/tmp/hello world/lib/page.ex"}

assert SupportURI.file_uri_to_path("file://localhost/tmp/project/lib/page.ex") ==
         {:ok, "/tmp/project/lib/page.ex"}

assert SupportURI.file_uri_to_path("untitled:Untitled-1") ==
         {:error, {:unsupported_uri_scheme, "untitled"}}

assert SupportURI.path_to_file_uri("/tmp/hello world") ==
         {:ok, "file:///tmp/hello%20world"}
```

- [ ] **Step 2: Run URI tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/support/uri_test.exs
```

Expected: FAIL because `PhoenixLS.Support.URI` does not exist.

- [ ] **Step 3: Implement URI helpers**

Create `PhoenixLS.Support.URI` with `file_uri_to_path/1`, `path_to_file_uri/1`, and bang variants for tests/fixtures. Use `URI.parse/1`, `URI.decode/1`, `Path.expand/1`, and `URI.encode/2` with a path-safe character predicate.

- [ ] **Step 4: Run URI tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/support/uri_test.exs
```

Expected: PASS.

## Task 2: Mix Project Locator

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/project/locator.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/project/locator_test.exs`

- [ ] **Step 1: Write failing locator tests**

Create tests that build temporary project fixtures using `tmp_dir` and `File.write!/2`:

```elixir
assert {:ok, result} = Locator.locate(file_uri)
assert result.root_path == project_root
assert result.root_uri == SupportURI.path_to_file_uri!(project_root)
assert result.mix_exs_path == Path.join(project_root, "mix.exs")
assert result.phoenix? == true
```

Also assert:

```elixir
assert Locator.locate(no_project_file_uri) == :error
assert Locator.locate("untitled:Untitled-1") == {:error, {:unsupported_uri_scheme, "untitled"}}
```

- [ ] **Step 2: Run locator tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/locator_test.exs
```

Expected: FAIL because `PhoenixLS.Project.Locator` does not exist.

- [ ] **Step 3: Implement locator**

Create `PhoenixLS.Project.Locator` with:

```elixir
defmodule Result do
  @enforce_keys [:root_path, :root_uri, :mix_exs_path, :phoenix?]
  defstruct [:root_path, :root_uri, :mix_exs_path, :umbrella_root_path, :umbrella_root_uri, phoenix?: false]
end
```

Implement:
- `locate/1`
- nearest `mix.exs` ancestor search
- optional umbrella parent discovery
- Phoenix dependency detection via `Code.string_to_quoted/1` and `Macro.prewalk/3`

- [ ] **Step 4: Run locator tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/locator_test.exs
```

Expected: PASS.

## Task 3: Manager Canonical Project Routing

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`

- [ ] **Step 1: Write failing manager locator tests**

Add tests asserting `Manager.ensure_project_for_uri/2`:
- starts an engine using the located project root URI when given a nested file URI
- reuses the same engine when called with the project root URI
- returns `:error` for files outside any Mix project

- [ ] **Step 2: Run manager tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs
```

Expected: FAIL because `ensure_project_for_uri/2` does not exist.

- [ ] **Step 3: Implement manager canonicalization**

Add:

```elixir
def ensure_project_for_uri(server \\ @default_name, uri) when is_binary(uri) do
  GenServer.call(server, {:ensure_project_for_uri, uri})
end
```

In the GenServer, call `Locator.locate/1`; when it succeeds, call the existing engine startup path with `result.root_uri`.

- [ ] **Step 4: Run manager tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs
```

Expected: PASS.

## Task 4: LSP Initialize Uses Located Project Root

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`

- [ ] **Step 1: Write failing LSP routing tests**

Update lifecycle tests to assert:
- `Server.init/2` assigns `project_root_uri: nil`
- initializing with a nested project directory URI assigns `project_root_uri` to the Mix project root URI
- initializing with a no-project URI keeps fallback document store and `project_root_uri: nil`

Update transport project document sync test to create a `mix.exs` fixture and assert opened documents land in `Names.document_store(project_root_uri)`.

- [ ] **Step 2: Run LSP tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
```

Expected: FAIL because `project_root_uri` is not assigned and initialize still routes by raw `root_uri`.

- [ ] **Step 3: Implement LSP located routing**

Update `Server.init/2` to assign `project_root_uri: nil`. Update `assign_project/2` to call `Manager.ensure_project_for_uri/2` and assign both `document_store` and `project_root_uri` when it succeeds.

- [ ] **Step 4: Run LSP tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
```

Expected: PASS.

## Task 5: Full Verification And Commit

**Files:**
- All changed files in this plan.

- [ ] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If it fails, run `cd server && mix format`, inspect the diff, then rerun.

- [ ] **Step 2: Run complete test suite**

Run:

```bash
cd server && mix test
```

Expected: PASS.

- [ ] **Step 3: Run warnings-as-errors compile**

Run:

```bash
cd server && mix compile --warnings-as-errors
```

Expected: PASS.

- [ ] **Step 4: Check no semantic regex was introduced**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls/project server/apps/phoenix_ls/lib/phoenix_ls/support server/apps/phoenix_ls/lib/phoenix_ls/lsp server/apps/phoenix_ls/test/phoenix_ls/project server/apps/phoenix_ls/test/phoenix_ls/support server/apps/phoenix_ls/test/phoenix_ls/lsp || true
```

Expected: no output.

- [ ] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-uri-project-locator.md server/apps/phoenix_ls/lib/phoenix_ls/support/uri.ex server/apps/phoenix_ls/lib/phoenix_ls/project/locator.ex server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/test/phoenix_ls/support/uri_test.exs server/apps/phoenix_ls/test/phoenix_ls/project/locator_test.exs server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
git commit -m "feat: locate mix projects for lsp routing"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers URI conversion, Mix root locating, AST-only Phoenix dependency detection, manager canonicalization, and LSP initialize routing. It intentionally does not implement workspace folders, file watchers, indexing, diagnostics, completion, or project code execution.
- Placeholder scan: No task uses TBD, TODO, or unspecified test instructions.
- Type consistency: The plan consistently uses `Support.URI.file_uri_to_path/1`, `Support.URI.path_to_file_uri/1`, `Project.Locator.locate/1`, `Manager.ensure_project_for_uri/2`, and `project_root_uri` assigns.
