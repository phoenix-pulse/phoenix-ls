# Source Only Phoenix Introspection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add source-backed facts for Phoenix routers, Ecto schemas, LiveView events, HEEx templates, and harder component declaration shapes.

**Architecture:** Keep all extraction source-only inside `PhoenixLS.Index.ElixirSource` and `PhoenixLS.Index.DocumentIndexer`. Add focused `PhoenixLS.Introspection.*` modules that consume already-parsed AST or document text and emit `PhoenixLS.Index.Fact` structs with URI, LSP range, and provenance. Do not compile projects, execute macros, or parse semantics with regex.

**Tech Stack:** Elixir, ExUnit, `Code.string_to_quoted/2`, existing `PhoenixLS.Index.Fact`, existing UTF-16 range helpers, and plain file/document metadata.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/introspection/router.ex`
  - Extract `:route` facts from `scope` blocks and Phoenix router macros such as `get`, `post`, `put`, `patch`, `delete`, and `live`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/introspection/schema.ex`
  - Extract `:schema`, `:schema_field`, and `:schema_association` facts from Ecto `schema` blocks.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
  - Extract `:live_view` and `:live_event` facts from modules using `Phoenix.LiveView` and `handle_event/3`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`
  - Extract `:template` facts from `.heex` documents.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
  - Preserve doc/default/values metadata.
  - Accept components with aliases/import-friendly metadata already available from source.
  - Keep malformed source behavior non-raising.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
  - Delegate to router, schema, and LiveView extractors for each module body.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/index/document_indexer.ex`
  - Index `.heex`/`phoenix-heex` documents as template facts.
- Add tests:
  - `server/apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs`
  - `server/apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs`
  - `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`
  - `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`
  - extend existing `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
  - extend existing `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

## Task 1: Router Facts

- [x] **Step 1: Write failing router tests**

Assert a router module produces source-backed facts for scoped `live` and HTTP routes:

```elixir
source = """
defmodule AppWeb.Router do
  use Phoenix.Router

  scope "/", AppWeb do
    pipe_through :browser
    live "/products/:id", ProductLive.Show, :show
    get "/products/:id/edit", ProductController, :edit
  end
end
"""
```

Expected route IDs include:
- `AppWeb.Router:live:/products/:id:AppWeb.ProductLive.Show:show`
- `AppWeb.Router:get:/products/:id/edit:AppWeb.ProductController:edit`

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs
```

Expected: FAIL because `PhoenixLS.Introspection.Router` does not exist and `ElixirSource` does not emit route facts.

- [x] **Step 3: Implement router extractor**

Create `PhoenixLS.Introspection.Router.facts_for_module_body/4`. Walk AST blocks, track `scope` path/module prefixes, ignore `pipe_through`, and emit `Fact` structs for literal route macros only. Unsupported dynamic route forms return no facts instead of raising.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 2: Schema Facts

- [x] **Step 1: Write failing schema tests**

Assert a schema module produces:
- one `:schema` fact for table `"products"`
- `:schema_field` facts for `field :name, :string` and `field :active, :boolean, default: true`
- a `:schema_association` fact for `belongs_to :account, App.Accounts.Account`

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs
```

Expected: FAIL because `PhoenixLS.Introspection.Schema` does not exist and `ElixirSource` does not emit schema facts.

- [x] **Step 3: Implement schema extractor**

Create `PhoenixLS.Introspection.Schema.facts_for_module_body/4`. Recognize literal `schema "table" do ... end`, `field`, `belongs_to`, `has_many`, and `has_one` declarations in the block. Preserve source range and options on facts.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 3: LiveView Event Facts

- [x] **Step 1: Write failing LiveView tests**

Assert a module using `Phoenix.LiveView` emits:
- one `:live_view` fact
- a `:live_event` fact for `handle_event("select-product", params, socket)`
- no event fact for dynamic event names

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs
```

Expected: FAIL because `PhoenixLS.Introspection.LiveView` does not exist and `ElixirSource` does not emit LiveView facts.

- [x] **Step 3: Implement LiveView extractor**

Create `PhoenixLS.Introspection.LiveView.facts_for_module_body/4`. Detect `use Phoenix.LiveView` or `use AppWeb, :live_view`, then emit source-backed event facts for literal `handle_event/3` names.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 4: Template Facts

- [x] **Step 1: Write failing template tests**

Assert `.heex` documents produce a `:template` fact with URI, range from start to end of document, and data containing `format: :heex`.

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: FAIL because template extraction is not implemented and `DocumentIndexer` ignores HEEx documents.

- [x] **Step 3: Implement template extraction and document indexing**

Create `PhoenixLS.Introspection.Template.facts/3`. Modify `DocumentIndexer.index/2` to reindex template documents by deleting stale URI facts and storing one template fact.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 5: Component Hardening

- [x] **Step 1: Write failing component hardening tests**

Assert component attr facts preserve `doc`, `default`, and `values` options, colocated modules still produce facts, and malformed source returns `{:error, {:parse_error, _}}` without stale facts.

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs
```

Expected: FAIL for any missing component metadata/hardening behavior.

- [x] **Step 3: Implement minimal hardening**

Keep declaration options intact in fact data and add tests around nested/colocated module extraction through the existing recursive module walker.

- [x] **Step 4: Verify GREEN**

Run the same focused command. Expected: PASS.

## Task 6: Full Verification And Commit

- [x] **Step 1: Format check**

Run:

```bash
cd server && mix format --check-formatted
```

- [x] **Step 2: Full test suite**

Run:

```bash
cd server && mix test
```

- [x] **Step 3: Warnings-as-errors compile**

Run:

```bash
cd server && mix compile --warnings-as-errors
```

- [x] **Step 4: Regex policy scan**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls server/apps/phoenix_ls/test/phoenix_ls --glob '!**/architecture/regex_policy_test.exs' || true
```

Expected: no output.

- [x] **Step 5: Commit**

Commit message:

```bash
git commit -m "feat: add source-only phoenix introspection facts"
```

## Self-Review

- Spec coverage: Covers objective items 10-14 and creates source facts needed by completion items 18-23.
- Placeholder scan: No TBD/TODO/fill-in steps.
- Type consistency: All extractors return `PhoenixLS.Index.Fact` structs and are routed through `ElixirSource` or `DocumentIndexer`.
