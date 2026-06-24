# Document Sync Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first implemented LSP text document synchronization surface for the Elixir v2 server.

**Architecture:** The server advertises only full text-document sync because the current document store owns whole-document open and replace operations. `PhoenixLS.LSP.Server` remains a thin protocol dispatcher and delegates document sync notifications to a focused `PhoenixLS.LSP.TextDocumentSync` module. The document-sync module receives the GenLSP LSP state, resolves the configured document store from assigns, and updates open document state without parsing source text or adding feature intelligence.

**Tech Stack:** Elixir, OTP GenServer, GenLSP 0.11.3, ExUnit.

---

## File Structure

- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
  - Advertise `text_document_sync` as `TextDocumentSyncOptions` with `open_close: true` and `change: TextDocumentSyncKind.full()`.
  - Keep completion, hover, definition, and other request capabilities unset.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Store `:document_store` in GenLSP assigns during init, defaulting to `PhoenixLS.Workspace.DocumentStore`.
  - Delegate `textDocument/didOpen`, `textDocument/didChange`, and `textDocument/didClose` notifications to `PhoenixLS.LSP.TextDocumentSync`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
  - Convert GenLSP notification structs into `DocumentStore.open/5`, `DocumentStore.replace/4`, and `DocumentStore.close/2` calls.
  - Treat only whole-document content changes as implemented.
  - Ignore unsupported ranged content changes for now because the server advertises full sync, not incremental sync.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`
  - Assert full text document sync is advertised.
  - Assert unimplemented feature capabilities remain unset.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
  - Assert `init/2` stores the default document store assign.
  - Update transport initialize expectation to include the implemented `textDocumentSync` capability.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`
  - Test direct callback behavior for open, full change, ranged-change ignore, and close.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs`
  - Test that JSON-RPC `textDocument/didOpen`, `didChange`, and `didClose` notifications update an isolated document store through GenLSP transport.

## Task 1: Advertise Implemented Full Text Sync

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`

- [ ] **Step 1: Write failing capability tests**

Replace the document-sync assertions in `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs` with:

```elixir
alias GenLSP.Enumerations.TextDocumentSyncKind
alias GenLSP.Structures.{ServerCapabilities, TextDocumentSyncOptions}

test "advertises full text document sync" do
  capabilities = Capabilities.build()

  assert %TextDocumentSyncOptions{} = sync = capabilities.text_document_sync
  assert sync.open_close == true
  assert sync.change == TextDocumentSyncKind.full()
  assert sync.will_save == nil
  assert sync.will_save_wait_until == nil
  assert sync.save == nil
end
```

Update `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs` in the callback initialize test:

```elixir
assert result.capabilities.text_document_sync.open_close == true
assert result.capabilities.text_document_sync.change == TextDocumentSyncKind.full()
```

Update the transport initialize expected capability map:

```elixir
"capabilities" => %{
  "experimental" => nil,
  "textDocumentSync" => %{
    "openClose" => true,
    "change" => TextDocumentSyncKind.full()
  }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: FAIL because `Capabilities.build/0` still returns `text_document_sync == nil`.

- [ ] **Step 3: Implement full sync capability**

Update `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`:

```elixir
alias GenLSP.Enumerations.TextDocumentSyncKind
alias GenLSP.Structures.{ServerCapabilities, TextDocumentSyncOptions}

def build do
  %ServerCapabilities{
    text_document_sync: %TextDocumentSyncOptions{
      open_close: true,
      change: TextDocumentSyncKind.full()
    }
  }
end
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: PASS.

## Task 2: Add Document Sync Callback Handler

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`

- [ ] **Step 1: Write failing callback tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs` with tests that:

```elixir
assert {:noreply, ^lsp} = TextDocumentSync.handle(open_notification, lsp)
assert {:ok, document} = DocumentStore.fetch(store, uri)
assert document.language_id == "phoenix-heex"
assert document.version == 1
assert document.text == "<div>Hello</div>"
```

Then test full change:

```elixir
assert {:noreply, ^lsp} = TextDocumentSync.handle(change_notification, lsp)
assert {:ok, document} = DocumentStore.fetch(store, uri)
assert document.version == 2
assert document.text == "<div>Hello Phoenix</div>"
```

Then test ranged change ignore:

```elixir
assert {:noreply, ^lsp} = TextDocumentSync.handle(ranged_change_notification, lsp)
assert {:ok, document} = DocumentStore.fetch(store, uri)
assert document.version == 1
assert document.text == "<div>Hello</div>"
```

Then test close:

```elixir
assert {:noreply, ^lsp} = TextDocumentSync.handle(close_notification, lsp)
assert DocumentStore.fetch(store, uri) == :error
```

Update `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs` so `init/2` asserts:

```elixir
assert LSP.assigns(initialized_lsp).document_store == PhoenixLS.Workspace.DocumentStore
```

- [ ] **Step 2: Run callback tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: FAIL because `PhoenixLS.LSP.TextDocumentSync` does not exist and `Server.init/2` has no `:document_store` assign.

- [ ] **Step 3: Implement callback handler and server delegation**

Create `PhoenixLS.LSP.TextDocumentSync` with `handle/2` clauses for `TextDocumentDidOpen`, `TextDocumentDidChange`, and `TextDocumentDidClose`.

Implementation details:

```elixir
defp document_store(lsp) do
  GenLSP.LSP.assigns(lsp).document_store
end
```

For full changes, use the final whole-document change in `content_changes`:

```elixir
defp full_text_change(content_changes) do
  content_changes
  |> Enum.reverse()
  |> Enum.find(fn
    %{range: _range} -> false
    %{"range" => _range} -> false
    %{text: text} when is_binary(text) -> true
    %{"text" => text} when is_binary(text) -> true
    _change -> false
  end)
end
```

Update `Server.init/2` to assign:

```elixir
document_store = Keyword.get(args, :document_store, PhoenixLS.Workspace.DocumentStore)

assign(lsp,
  document_store: document_store,
  exit_code: 1,
  exit_handler: exit_handler,
  root_uri: nil
)
```

Add notification delegation clauses before the fallback:

```elixir
def handle_notification(%TextDocumentDidOpen{} = notification, lsp),
  do: TextDocumentSync.handle(notification, lsp)

def handle_notification(%TextDocumentDidChange{} = notification, lsp),
  do: TextDocumentSync.handle(notification, lsp)

def handle_notification(%TextDocumentDidClose{} = notification, lsp),
  do: TextDocumentSync.handle(notification, lsp)
```

- [ ] **Step 4: Run callback tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: PASS.

## Task 3: Verify Document Sync Over GenLSP Transport

**Files:**
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs`

- [ ] **Step 1: Write failing transport test**

Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs` with a test that:

```elixir
test "GenLSP transport applies open, full change, and close notifications" do
  store = Module.concat(__MODULE__, DocumentStore)
  {:ok, _store_pid} = start_supervised({DocumentStore, name: store})

  test_server = GenLSP.Test.server(Server, init_args: [document_store: store])
  test_client = GenLSP.Test.client(test_server)

  uri = "file:///tmp/page.html.heex"

  GenLSP.Test.notify(test_client, %{
    jsonrpc: "2.0",
    method: "textDocument/didOpen",
    params: %{
      textDocument: %{
        uri: uri,
        languageId: "phoenix-heex",
        version: 1,
        text: "<div>Hello</div>"
      }
    }
  })

  assert_eventually(fn ->
    assert {:ok, document} = DocumentStore.fetch(store, uri)
    assert document.version == 1
    assert document.text == "<div>Hello</div>"
  end)

  GenLSP.Test.notify(test_client, %{
    jsonrpc: "2.0",
    method: "textDocument/didChange",
    params: %{
      textDocument: %{uri: uri, version: 2},
      contentChanges: [%{text: "<div>Hello Phoenix</div>"}]
    }
  })

  assert_eventually(fn ->
    assert {:ok, document} = DocumentStore.fetch(store, uri)
    assert document.version == 2
    assert document.text == "<div>Hello Phoenix</div>"
  end)

  GenLSP.Test.notify(test_client, %{
    jsonrpc: "2.0",
    method: "textDocument/didClose",
    params: %{textDocument: %{uri: uri}}
  })

  assert_eventually(fn ->
    assert DocumentStore.fetch(store, uri) == :error
  end)
end
```

Use a local `assert_eventually/1` helper with a short retry loop so async notification handling is deterministic.

- [ ] **Step 2: Run transport test and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs
```

Expected before Task 2 implementation: FAIL because sync notifications are ignored. If Task 2 has already been implemented, temporarily reverting the delegation lines in `Server.handle_notification/2` should make this test fail for the expected reason, then restore the delegation lines.

- [ ] **Step 3: Run transport test and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs
```

Expected: PASS.

## Task 4: Full Verification And Commit

**Files:**
- All changed files in this plan.

- [ ] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If it fails, run `cd server && mix format`, inspect the diff, then rerun `mix format --check-formatted`.

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

- [ ] **Step 4: Inspect git diff**

Run:

```bash
git diff --stat
git diff -- server/apps/phoenix_ls/lib/phoenix_ls/lsp server/apps/phoenix_ls/test/phoenix_ls/lsp docs/superpowers/plans/2026-06-24-document-sync-foundation.md
```

Expected: only the document-sync plan, capability update, server delegation, document-sync module, and document-sync tests changed.

- [ ] **Step 5: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-document-sync-foundation.md server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/text_document_sync.ex server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/text_document_sync_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/document_sync_transport_test.exs
git commit -m "feat: add full text document sync"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan covers full text sync capability, open/change/close handlers, isolated document store injection, callback tests, transport tests, and full verification. It intentionally does not add completion, hover, definition, incremental range edits, parsing, indexing, diagnostics, or source intelligence.
- Placeholder scan: No implementation step uses placeholders such as TBD, TODO, or "add appropriate tests" without concrete commands and target behavior.
- Type consistency: The plan uses the generated GenLSP modules present in this checkout: `TextDocumentDidOpen`, `TextDocumentDidChange`, `TextDocumentDidClose`, `DidOpenTextDocumentParams`, `DidChangeTextDocumentParams`, `DidCloseTextDocumentParams`, `TextDocumentItem`, `VersionedTextDocumentIdentifier`, and `TextDocumentIdentifier`.
