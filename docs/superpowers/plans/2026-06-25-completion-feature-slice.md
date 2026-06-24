# Completion Feature Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand completion from local component-only results into source-only Phoenix completions backed by indexed route, schema, LiveView, assign, component, and snippet facts.

**Architecture:** Keep `PhoenixLS.LSP.Completion` as the request boundary and add small pure providers under `PhoenixLS.Features.Completion`. Providers receive `PhoenixLS.HEEx.CursorContext` plus index facts and return LSP `CompletionItem` structs. Completion resolve stays deterministic by carrying documentation/detail data on completion item `data`.

**Tech Stack:** Elixir, ExUnit, GenLSP completion structs, existing source-only index facts, no semantic regex parsing.

---

## Scope Decisions

- Items 15-17 are already implemented for local component attrs, slots, and slot attrs; this slice keeps them green.
- Item 20 router helper completions are not included in v2 core for now. Verified `~p` route completions replace helper-name completions because Phoenix 1.7+ routes users toward verified routes and helper names require older router-generation semantics.
- Item 24 survives as a small static HTML/Phoenix snippet provider, not a large HTML language service.
- Item 26 is implemented as a narrow generic Elixir fallback provider, not a full ElixirSense dependency.

## File Structure

- Modify `server/apps/phoenix_ls/lib/phoenix_ls/heex/cursor_context.ex`
  - Track expression prefix text for assign, route, schema, and fallback providers.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
  - Emit `:assign` facts for literal `assign(socket, :name, value)` calls.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/components.ex`
  - Add remote component tag/attribute completions using alias/import facts.
  - Include documentation metadata for resolve.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/routes.ex`
  - Complete verified `~p` route paths from `:route` facts.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/schemas.ex`
  - Complete schema/form fields from `:schema_field` facts.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/live_view.ex`
  - Complete assigns and `phx-*` event values.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/snippets.ex`
  - Complete selected HTML tags and Phoenix attributes/snippets.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/elixir_fallback.ex`
  - Complete a short, explicit list of generic Elixir names in expression contexts.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/resolve.ex`
  - Add docs/details to completion items using preserved data.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
  - Aggregate providers.
  - Handle `completionItem/resolve`.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
  - Advertise resolve provider.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/dispatcher.ex`
  - Route `completionItem/resolve`.

## Task 1: Cursor Context Expression Prefix

- [x] **Step 1: Write failing cursor context tests**

Assert expression contexts preserve prefixes for:
- `{@sel|ected_id}`
- `<.link navigate={~p"/prod|ucts"} />`
- `<.input field={@form[:na|me]} />`

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/heex/cursor_context_test.exs
```

- [x] **Step 3: Implement prefix tracking**

Track expression graphemes while in expression state and expose them through `CursorContext.prefix`.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 2: Completion Providers

- [x] **Step 1: Write failing provider tests**

Extend completion tests to assert:
- `<CoreComponents.bu| />` completes `CoreComponents.button`.
- `<CoreComponents.button |>` completes attrs from the remote component.
- `<.link navigate={~p"/prod|"} />` completes `/products/:id`.
- `<.input field={@form[:na|]} />` completes `name`.
- `{@sele|}` completes `@selected_id`.
- `<button phx-click="sel|">` completes `select-product`.
- `<di|>` completes `div`.
- `<button phx-|>` completes `phx-click`.
- `{to_s|}` completes `to_string`.

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs
```

- [x] **Step 3: Implement providers**

Add pure provider modules for routes, schemas, LiveView assigns/events, snippets, and fallback. Extend component provider for aliases/imports and remote component tags.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 3: LSP Aggregation And Resolve

- [x] **Step 1: Write failing LSP tests**

Assert:
- initialization advertises `completionProvider.resolveProvider: true`
- transport returns event or route completions from indexed facts
- `completionItem/resolve` returns documentation for component attrs

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs
```

- [x] **Step 3: Implement aggregation and resolve routing**

Call every pure completion provider from `PhoenixLS.LSP.Completion.handle/2`. Add `Completion.resolve/2`, advertise resolve support, and route `GenLSP.Requests.CompletionItemResolve`.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 4: Verification And Commit

- [x] **Step 1: Format check**

Run `cd server && mix format --check-formatted`.

- [x] **Step 2: Full test suite**

Run `cd server && mix test`.

- [x] **Step 3: Warnings-as-errors compile**

Run `cd server && mix compile --warnings-as-errors`.

- [x] **Step 4: Regex policy scan**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls server/apps/phoenix_ls/test/phoenix_ls --glob '!**/architecture/regex_policy_test.exs' || true
```

Expected: no output.

- [x] **Step 5: Commit**

Commit message:

```bash
git commit -m "feat: expand phoenix completion providers"
```

## Self-Review

- Spec coverage: Covers items 18, 19, 21, 22, 23, 24, 25, and 26; items 15-17 remain covered by existing component completion tests. Item 20 is explicitly excluded from v2 core in favor of verified `~p`.
- Placeholder scan: No TBD/TODO/fill-in steps.
- Type consistency: Providers return `GenLSP.Structures.CompletionItem` and route through `PhoenixLS.LSP.Completion`.
