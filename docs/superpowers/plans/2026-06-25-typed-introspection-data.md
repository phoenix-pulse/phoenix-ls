# Typed Introspection Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace generic `Fact.data` maps for Phoenix introspection facts with typed structs for router, schema, component, template, LiveView, event, assign, alias, and import data.

**Architecture:** Keep `PhoenixLS.Index.Fact` generic, but make every Phoenix introspection extractor store module-specific structs in `data`. Struct fields preserve the current names so completion, hover, diagnostics, definitions, and explorer payloads continue to use existing dot access. Test expectations should assert struct modules instead of anonymous maps.

**Tech Stack:** Elixir, ExUnit, existing source-only introspection modules, existing `PhoenixLS.Index.Fact`.

---

### Task 1: Router, Template, And LiveView Data Structs

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/router.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`

- [x] **Step 1: Write failing struct expectations**

Assert route data is `%PhoenixLS.Introspection.Router.Route{}`, template data is `%PhoenixLS.Introspection.Template.Template{}`, live-view data is `%PhoenixLS.Introspection.LiveView.LiveView{}`, event data is `%PhoenixLS.Introspection.LiveView.Event{}`, and assign data is `%PhoenixLS.Introspection.LiveView.Assign{}`.

- [x] **Step 2: Verify tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`

- [x] **Step 3: Implement structs and use them in facts**

Define nested structs inside the owning introspection modules and replace map literals in `Fact.new!/1` calls with struct values.

- [x] **Step 4: Verify tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/router_test.exs apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`

### Task 2: Schema Data Structs

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/schema.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs`

- [x] **Step 1: Write failing schema struct expectations**

Assert schema data is `%PhoenixLS.Introspection.Schema.Schema{}`, field data is `%PhoenixLS.Introspection.Schema.Field{}`, and association data is `%PhoenixLS.Introspection.Schema.Association{}`.

- [x] **Step 2: Verify schema tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs`

- [x] **Step 3: Implement schema structs and use them in facts**

Define nested structs in `PhoenixLS.Introspection.Schema` and replace schema map data with typed structs.

- [x] **Step 4: Verify schema tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs`

### Task 3: Component Data Structs

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/component.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 1: Write failing component struct expectations**

Assert component data is `%PhoenixLS.Introspection.Component.Component{}`, attr data is `%PhoenixLS.Introspection.Component.Attribute{}`, slot data is `%PhoenixLS.Introspection.Component.Slot{}`, slot attr data is `%PhoenixLS.Introspection.Component.SlotAttribute{}`, alias data is `%PhoenixLS.Introspection.Component.Alias{}`, and import data is `%PhoenixLS.Introspection.Component.Import{}`.

- [x] **Step 2: Verify component tests fail**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

- [x] **Step 3: Implement component structs and use them in facts**

Define nested structs in `PhoenixLS.Introspection.Component`, update `put_component_doc/2` to update the struct with `%{fact | data: %{fact.data | doc: doc}}`, and replace map fact data with structs.

- [x] **Step 4: Verify component tests pass**

Run: `cd server && mix test apps/phoenix_ls/test/phoenix_ls/index/elixir_source_test.exs apps/phoenix_ls/test/phoenix_ls/index/document_indexer_test.exs`

### Task 4: Slice Verification

- [x] Run `cd server && mix format --check-formatted`
- [x] Run `cd server && mix test`
- [x] Run `cd server && mix compile --warnings-as-errors`
- [x] Run `rg -n "Regex|~r|:re\\.|=~" server/apps/phoenix_ls/lib server/apps/phoenix_ls/test`
- [x] Commit the local slice after verification passes
