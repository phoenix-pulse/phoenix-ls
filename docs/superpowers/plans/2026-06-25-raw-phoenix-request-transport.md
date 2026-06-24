# Raw Phoenix Request Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make raw JSON-RPC `phoenix/*` editor explorer requests work through the runtime transport without patching ignored `gen_lsp` dependency code.

**Architecture:** Add a PhoenixLS-owned `GenLSP.Communication.Adapter` wrapper that rewrites incoming raw `phoenix/*` request packets into `workspace/executeCommand` packets before GenLSP request decoding. Route `workspace/executeCommand` commands whose command starts with `phoenix/` back into the existing `PhoenixLS.LSP.CustomRequest` handler. Keep payload building unchanged.

**Tech Stack:** Elixir, ExUnit, GenLSP communication adapter behaviour, existing `PhoenixLS.LSP.PhoenixRequests`.

---

### Task 1: Communication Adapter Normalization

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/custom_request_adapter.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_adapter_test.exs`

- [x] **Step 1: Write failing adapter tests**

Cover that an incoming JSON body with method `phoenix/listRoutes` becomes a JSON body with method `workspace/executeCommand`, command `phoenix/listRoutes`, and original params as the first argument. Also cover that non-Phoenix requests pass through unchanged.

- [x] **Step 2: Verify adapter tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_adapter_test.exs`

- [x] **Step 3: Implement `PhoenixLS.LSP.CustomRequestAdapter`**

Implement `GenLSP.Communication.Adapter`, wrap an `:inner` adapter option, delegate `init/1`, `listen/1`, `read/2`, and `write/2`, and normalize only decoded JSON-RPC requests with an `id` and `method` beginning with `phoenix/`.

- [x] **Step 4: Verify adapter tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_adapter_test.exs`

### Task 2: Dispatcher Execute Command Bridge

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`

- [x] **Step 1: Write failing dispatcher bridge test**

Add a test that builds `%GenLSP.Requests.WorkspaceExecuteCommand{}` with command `phoenix/listSchemas` and asserts the dispatcher returns the same empty-list no-project result as the custom request path.

- [x] **Step 2: Verify dispatcher bridge test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`

- [x] **Step 3: Implement bridge**

Handle `%GenLSP.Requests.WorkspaceExecuteCommand{params: %{command: "phoenix/" <> _}}` in `PhoenixLS.LSP.Dispatcher` by constructing `%PhoenixLS.LSP.CustomRequest{id: request.id, method: command, params: first_argument_map_or_empty}` and delegating to `PhoenixLS.LSP.PhoenixRequests.handle/2`.

- [x] **Step 4: Verify dispatcher bridge test passes**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`

### Task 3: Runtime Raw Transport Coverage

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/runtime.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs`

- [x] **Step 1: Write failing runtime raw request test**

Use a scripted communication adapter inside `Runtime.start_link/1`, send an actual raw `phoenix/listSchemas` JSON body to the runtime reader, and assert the outgoing JSON-RPC response is `%{"id" => 7, "result" => []}`.

- [x] **Step 2: Verify runtime raw request test fails**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs`

- [x] **Step 3: Make runtime default to custom adapter**

Add `Runtime.default_communication/0` returning `{PhoenixLS.LSP.CustomRequestAdapter, inner: {GenLSP.Communication.Stdio, []}}` and use it as the default `communication` option.

- [x] **Step 4: Verify runtime tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs`

### Task 4: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
