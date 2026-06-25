# Phoenix LS Final 100 Percent Completion Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Phoenix LS v2 to 100% of the intended Phoenix companion-server scope: Phoenix, HEEx, LiveView, controller, template, schema, router, component, slot, asset, and generator intelligence backed by source-ranged facts, verified in generated Phoenix 1.8 apps and real editor dogfood. This does not mean generic Elixir, generic HTML, formatting, rename, references, symbols, or semantic-token parity with Expert.

**Architecture:** Keep the manager/engine split. New semantics must flow through `source parser -> source-ranged facts -> shared lookup/docs/payload helpers -> LSP providers/custom requests`. Feature providers must not grow their own Phoenix parsing. Component and slot docs use one shared formatter. Controller intelligence gets one controller fact owner. LiveView lifecycle intelligence gets one lifecycle fact owner. Confidence belongs in fact `data` or `provenance`, because `PhoenixLS.Index.Fact` only has `kind`, `id`, `uri`, `range`, `provenance`, and `data`.

**Tech Stack:** Elixir, ExUnit, GenLSP, Phoenix 1.8 generated fixtures, official Phoenix/LiveView documentation, VS Code TypeScript launcher, Neovim Lua launcher, installed VSIX dogfood.

---

## Evidence Base

- Current v2 code advertises completion, completion resolve, signature help, quick fixes, hover, definition, full text sync, and workspace folders in `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`.
- Current v2 tests already cover component tags, attrs, slots, slot attrs, source-scoped slot completions, slot definitions, slot hovers, slot signature help, missing/unknown slot diagnostics, and slot quick fixes.
- Current v2 has focused modules under `server/apps/phoenix_ls/lib/phoenix_ls/features/completion`, `features/diagnostics`, `features/code_action`, `features/phoenix_requests`, and `introspection`.
- Old TypeScript server is evidence, not a contract. Keep its user-facing lessons for controller assigns, richer docs, special attrs, JS commands, event-aware attribute ranking, and real-world completions. Do not port its semantic regex fallback or old layout.
- Phoenix 1.8 docs emphasize generated `CoreComponents`, simplified generators, layout-as-function-component behavior, scopes, and generated-app dogfood. See:
  - https://phoenix.hexdocs.pm/components.html
  - https://www.phoenixframework.org/blog/phoenix-1-8-released
  - https://github.com/phoenixframework/phoenix/blob/main/CHANGELOG.md
- LiveView docs emphasize function components, `attr/3`, `slot/3`, `~H`, `embed_templates`, `start_async/3`, `handle_async/3`, colocated hooks, colocated JS, colocated CSS, and JS commands. See:
  - https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html
  - https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html
  - https://phoenix-live-view.hexdocs.pm/js-interop.html
  - https://phoenixframework.org/blog/phoenix-liveview-1-2-released
  - https://github.com/phoenixframework/phoenix_live_view/blob/main/CHANGELOG.md

---

## Completion Definition

Phoenix LS v2 is 100% complete for this scope when all of these are true:

- Every Phoenix-owned LSP feature works in both `.heex` files and `~H` sigils inside `.ex` files.
- Supported LSP surfaces are complete for Phoenix-owned semantics: completion, resolve, hover, definition, signature help, diagnostics, quick fixes, and custom explorer requests.
- Component, attr, slot, slot attr, built-in component, special attr, Phoenix attr, route, schema, form, assign, event, hook, upload, colocated asset, LiveView lifecycle, controller, render, template, and layout workflows are covered by source-ranged facts or documented as deliberate non-goals.
- Completion docs and hover docs use shared markdown builders, not duplicated prose across providers.
- Diagnostics are emitted only for exact or high-confidence facts. Medium or low-confidence inference may power hover, explorer, and completion, but must not create scary diagnostics.
- Real Phoenix 1.8 generated apps, umbrella fixtures, broken syntax fixtures, missing deps fixtures, large stress fixtures, and installed VSIX dogfood all pass.
- The old TypeScript server has been mined and closed: each user-facing behavior is either implemented in v2, replaced by a cleaner v2 behavior, or explicitly marked out of scope.

---

## Current Status

| Area | Status | Honest note |
| --- | --- | --- |
| Component tag completions | Strong | Core support exists; rich insertion snippets need polish. |
| Component attr completions | Strong | `.input` attr completion works in `~H`; richer resolve/hover docs need polish. |
| Slot completions | Core complete | Source-scoped slot and slot-attr completion, hover, definition, signature help, diagnostics, and code actions are covered. Rich completion docs and required-attr snippets remain polish. |
| Generated Phoenix `CoreComponents` | Partial | Generated `header`, `list`, `back`, `modal`, `simple_form`, `input`, and similar facts have tests, but Phoenix 1.8 generator drift needs real generated app verification. |
| Built-in components such as `.link`, `.form`, `.live_component` | Partial | Completions and some hovers exist; `.input`/built-in rich hover in `~H` is not good enough yet. |
| Special HEEx attrs `:for`, `:if`, `:let`, `:key` | Partial | Some behavior exists; docs, scoped variables, `:let` propagation, and `phx-no-format` need closure. |
| Phoenix attrs and `phx-value-*` | Partial | Schema-backed `phx-value-*` exists. Element-aware/event-aware ranking, docs consistency, and validation matrix need closure. |
| Routes and verified routes | Strong | Keep extending only for Phoenix-specific navigation and controller graph links. |
| Schemas and assign fields | Strong/partial | Schema facts exist; controller assigns, changesets, embedded forms, and `inputs_for` need more depth. |
| LiveView events and assigns | Strong/partial | `handle_event`, `handle_info` function facts, direct assigns, streams, uploads, hooks, navigation exist; `handle_async`, `start_async`, `attach_hook`, `temporary_assigns`, message facts, and lifecycle docs need closure. |
| Uploads/hooks/colocated assets | Strong/partial | Current modules exist; LiveView 1.2 colocated CSS and upload callback shapes need final verification. |
| Controller-render-template intelligence | Missing/partial | Current render references exist; controller action/render/assign/layout/plug graph is the largest remaining semantic gap. |
| Custom explorer requests | Strong/partial | Existing lists work; controller graph and richer relationship payloads remain. |
| Editor packaging and dogfood | Strong/partial | Existing bundled server and VS Code dogfood scripts exist; final gate needs a complex generated Phoenix 1.8 app and installed VSIX checks. |
| Old TS parity closure | Missing process | Need a tracked evidence matrix so old TS lessons are intentionally closed without treating TS as a parity contract. |

---

## Phase 1: Evidence Matrix And Scope Closure

**Files:**
- Create: `docs/phoenix-ls-feature-evidence-matrix.md`
- Modify: `docs/phoenix-docs-lsp-feature-findings.md`
- Modify: `docs/expert-companion-mode.md`
- Modify: `docs/elixir-v2-scope-matrix.md`
- Modify: `docs/post-roadmap-phoenix-intelligence.md`

- [ ] Create a feature evidence matrix with these columns: `feature`, `current status`, `v2 files`, `tests`, `old TS evidence`, `Phoenix docs evidence`, `decision`, `remaining work`.
- [ ] Include every old TS user-facing feature captured before `packages/language-server` removal, especially controller assigns, special attrs, slot snippets/docs, event-aware Phoenix attrs, element-aware ranking, JS commands, phx-value completions, streams, template diagnostics, route helpers, and Emmet.
- [ ] Mark Emmet, generic HTML language service behavior, generic Elixir references, rename, formatting, semantic tokens, and workspace symbols as out of scope unless a future Phoenix-specific design is approved.
- [ ] Update the three original docs so completed items are no longer shown as future work, and remaining items point to this plan.
- [ ] Verify docs do not contain stale claims:

```bash
rg -n "build-now|later|TODO|TBD|parity contract|regex fallback" docs/phoenix-docs-lsp-feature-findings.md docs/expert-companion-mode.md docs/elixir-v2-scope-matrix.md docs/post-roadmap-phoenix-intelligence.md docs/phoenix-ls-feature-evidence-matrix.md
```

Expected: only intentional historical references remain.

---

## Phase 2: Component, Slot, And Built-In Component UX Polish

This phase does not rebuild core slot intelligence. Slots are already a core-complete area. It closes the polish gap: rich docs, resolve behavior, snippets, and generated component drift.

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/component_docs.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/hover.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/signature_help.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/components.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/built_in_components.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/resolve.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/signature_help_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/components_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/resolve_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/hover_transport_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs`

- [ ] Add failing tests proving `.input` hover inside `~H` includes its attrs, types, required/default/value docs, and source component information.
- [ ] Add failing tests proving `.link`, `.form`, and `.live_component` hover/resolve docs are useful in both `.heex` and `~H`.
- [ ] Add failing tests proving slot completion resolve includes parent component, required status, slot docs, slot attrs, required slot attrs, and a minimal example.
- [ ] Add failing tests for slot completion insert text:

```elixir
assert item.label == ":item"
assert item.insert_text =~ ":item"
assert item.insert_text_format == InsertTextFormat.snippet()
```

- [ ] Decide and test the `:inner_block` completion policy. If a component explicitly declares `slot :inner_block`, completions may show it only when it is useful and not noisy; implicit inner blocks must not be fabricated as named slot completions.
- [ ] Implement `PhoenixLS.Features.ComponentDocs` with one markdown API for components, attrs, slots, slot attrs, and built-ins.
- [ ] Refactor hover, signature help, and completion resolve to call `ComponentDocs`; remove duplicated doc string formatting from feature modules.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/features/hover_test.exs test/phoenix_ls/features/signature_help_test.exs test/phoenix_ls/features/completion/components_test.exs test/phoenix_ls/features/completion/resolve_test.exs test/phoenix_ls/lsp/hover_transport_test.exs test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: component, slot, slot attr, and built-in docs are consistent across hover, signature help, completion resolve, `.heex`, and `~H`.

---

## Phase 3: HEEx Special Attributes, Scoped Variables, And Dynamic Attrs

**Files:**
- Create or extend: `server/apps/phoenix_ls/lib/phoenix_ls/heex/scope.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/special_attrs.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/phoenix.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/phx_values.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/phoenix_attrs.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/heex_structure.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/heex/scope_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`

- [ ] Add failing completion tests for `:for`, `:if`, `:let`, `:key`, and `phx-no-format` in `.heex` and `~H`.
- [ ] Add failing tests proving `:for={product <- @products}` exposes `product` as a scoped variable for body completions and `phx-value-*` field completions.
- [ ] Add failing tests proving tuple patterns in `:for`, `Enum.with_index/1`, and slot `:let` expose the correct variable names without regex parsing.
- [ ] Add failing tests proving dynamic attr maps such as `<div {@attrs}>` and `<.input {@rest}>` do not trigger unknown attr diagnostics.
- [ ] Implement scoped-variable extraction in `HEEx.Scope` using parsed HEEx tags and quoted Elixir expressions from attr values.
- [ ] Implement `SpecialAttrs` completion metadata in one module, then aggregate it from `Completion.Phoenix`.
- [ ] Keep diagnostics conservative: missing `:key` suggestions are OK for exact `:for` facts; do not warn on complex dynamic comprehensions.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/heex/scope_test.exs test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/features/diagnostics_test.exs
```

Expected: special attrs are documented, scoped, and safe in `.heex` and `~H`.

---

## Phase 4: Controller, Render, Template, Layout, And Assign Graph

This is the largest missing semantic area and the first priority after UX polish.

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/controller.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/controller/actions.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/controller/renders.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/controller/assigns.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/controller/plugs.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/index/elixir_source.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/assign_fields.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/hover.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/definition.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/templates.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/templates.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/controller_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/definition_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/*_transport_test.exs`

- [ ] Add failing tests for these facts:

```elixir
:controller
:controller_action
:controller_render
:controller_assign
:controller_layout
:controller_plug_assign
```

- [ ] Use `data.confidence` or `provenance.confidence`; do not add a top-level `%Fact{confidence: ...}` unless the whole index is intentionally refactored.
- [ ] Extract exact controller action facts from `def index(conn, params)` and guarded clauses.
- [ ] Extract exact render facts from:

```elixir
render(conn, :show)
render(conn, :show, product: product)
render(assign(conn, :product, product), :show)
conn |> assign(:product, product) |> render(:show)
Phoenix.Controller.render(conn, MyAppWeb.ProductHTML, :show, product: product)
```

- [ ] Bind render facts to embedded Phoenix 1.7/1.8 templates under `controllers/*_html/*.html.heex`, older `templates/*/*.html.heex`, and explicit view modules.
- [ ] Extract direct assigns from `assign/3`, `assign/2`, render keyword assigns, and pipeline assign calls.
- [ ] Add schema-aware controller assign field completions in templates, reusing `Completion.SchemaFacts`.
- [ ] Add hover and definition from `@product` in a controller-rendered template back to the controller assign fact when confidence is exact or high.
- [ ] Extend missing template diagnostics and quick fixes through existing template diagnostics, not a parallel implementation.
- [ ] Keep plug/pipeline propagated assigns at medium confidence until proven exact. Use them for explorer and hover first; do not emit missing-assign diagnostics from them.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/introspection/controller_test.exs test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/features/hover_test.exs test/phoenix_ls/features/definition_test.exs test/phoenix_ls/features/diagnostics_test.exs
mix test test/phoenix_ls/lsp/completion_transport_test.exs test/phoenix_ls/lsp/hover_transport_test.exs test/phoenix_ls/lsp/definition_transport_test.exs test/phoenix_ls/lsp/diagnostics_transport_test.exs test/phoenix_ls/lsp/code_action_transport_test.exs
```

Expected: controller-rendered templates get assign completion, hover, definition, missing template diagnostics, and quick fixes without false errors on dynamic render cases.

---

## Phase 5: Forms, Changesets, Embedded Forms, And Phoenix 1.8 Generators

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/schema.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/form_fields.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/assign_fields.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/changeset.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/schema_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/changeset_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs`

- [ ] Add failing tests proving `.input field={@form[:name]}` and `.input field={f[:name]}` complete generated schema fields in `.heex` and `~H`.
- [ ] Add failing tests for `Phoenix.Component.to_form/2`, `Phoenix.Component.form/1`, `inputs_for`, nested embedded schemas, and association fields.
- [ ] Extract changeset validation facts for exact calls such as `validate_required/2`, `validate_length/3`, `validate_number/3`, and `unique_constraint/3`.
- [ ] Use changeset facts for hover/explorer first. Only add diagnostics when the source fact is exact and the missing field is unambiguous.
- [ ] Verify against Phoenix 1.8 generated `phx.gen.html`, `phx.gen.live`, and `phx.gen.auth` output.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/introspection/schema_test.exs test/phoenix_ls/introspection/changeset_test.exs test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: generated and custom Phoenix forms produce useful, schema-aware completions without running project code.

---

## Phase 6: LiveView Lifecycle, Async, Hooks, Temporary Assigns, And Messages

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/lifecycle.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/assigns.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/live_view.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/live_views.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`

- [ ] Add failing lifecycle function tests for `handle_async/3`, `handle_call/3`, `handle_cast/2`, and guarded clauses where applicable.
- [ ] Add failing async fact tests for `assign_async/3`, `assign_async/4`, `start_async/3`, `start_async/4`, and matching `handle_async/3`.
- [ ] Add failing tests for `temporary_assigns` returned from `mount/3` and `render/1` assign behavior where statically knowable.
- [ ] Add failing tests for `attach_hook/4` with `:handle_event`, `:handle_params`, and `:after_render` lifecycle points.
- [ ] Add message facts for literal `handle_info(:tick, socket)`, `handle_info("topic", socket)`, and tuple heads where useful for completion/explorer. Do not mix them with client `phx-*` events.
- [ ] Use lifecycle facts in LiveView explorer payloads and completions.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/introspection/live_view_test.exs test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/features/phoenix_requests_test.exs
```

Expected: LiveView lifecycle coverage matches modern LiveView docs and avoids confusing server messages with browser events.

---

## Phase 7: Phoenix.LiveView.JS And Phoenix Attribute UX

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/live_view/js_commands.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/live_view_js.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/html_attributes.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/phoenix_attrs.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/hover.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/hover_test.exs`

- [ ] Add failing tests for `JS.show`, `JS.hide`, `JS.toggle`, class commands, attribute commands, focus commands, `JS.push`, `JS.navigate`, `JS.patch`, `JS.dispatch`, and `JS.exec` completion docs.
- [ ] Add failing tests for pipe-chain JS completions after `|>`.
- [ ] Add option-name completions for exact JS command call positions, such as `to:`, `transition:`, `time:`, `display:`, `value:`, `target:`, and `loading:`.
- [ ] Add validation only for exact invalid option names. Do not validate arbitrary Elixir expressions.
- [ ] Add element-aware Phoenix attr ranking from the parsed tag name: form-specific attrs first on `form`, focus attrs first on `input`/`button`, general attrs later.
- [ ] Add event-aware ranking only when the related LiveView has literal events. Do not use emoji in labels/details unless the project UI standard explicitly chooses it.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/hover_test.exs
```

Expected: JS and Phoenix attr UX is rich, context-aware, and quiet when context is uncertain.

---

## Phase 8: Uploads, Hooks, Colocated JS, And Colocated CSS Closure

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/uploads.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/uploads.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/hooks.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/colocated_assets.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/asset/hooks.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/colocated_assets.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/colocated_assets.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/asset_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`

- [ ] Add failing tests for LiveView 1.2 colocated CSS:

```heex
<style :type={MyAppWeb.ColocatedCSS}>
  .row { color: red; }
</style>
```

- [ ] Add failing tests for `Phoenix.LiveView.ColocatedHook`, `Phoenix.LiveView.ColocatedJS`, project-specific aliases, and dot-prefixed hook names.
- [ ] Add upload callback shape tests for `allow_upload/3`, `consume_uploaded_entries/3`, `consume_uploaded_entry/3`, `cancel_upload/3`, `uploaded_entries/2`, `upload_errors/1`, and `upload_errors/2`.
- [ ] Keep JS/CSS parsing conservative and isolated. No general JS or CSS language server behavior.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/introspection/live_view_test.exs test/phoenix_ls/introspection/template_test.exs test/phoenix_ls/introspection/asset_test.exs test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/phoenix_requests_test.exs
```

Expected: colocated assets and uploads match LiveView 1.2 behavior with no broad JS/CSS scope creep.

---

## Phase 9: Explorer And Custom Request Graph

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/controllers.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/payload.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/phoenix_requests.ex`
- Modify: `packages/vscode-extension/src/tree-view-provider.ts` or current explorer provider file
- Modify: `packages/nvim-plugin/lua/phoenix-pulse/init.lua`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/phoenix_requests_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/custom_request_adapter_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/runtime_test.exs`
- Test: `packages/vscode-extension/src/tree-view-provider.test.ts`
- Test: `packages/nvim-plugin/test-*.lua`

- [ ] Add `phoenix/listControllers` or `phoenix/listControllerGraph` after the controller facts exist.
- [ ] Include controller module, action, render target, template path, assigns, related route, layout, confidence, and locations.
- [ ] Enrich existing component payloads with slot attrs and docs only through shared payload helpers.
- [ ] Keep custom request payload contracts stable and tested.
- [ ] Run:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/features/phoenix_requests_test.exs test/phoenix_ls/lsp/custom_request_test.exs test/phoenix_ls/lsp/custom_request_adapter_test.exs test/phoenix_ls/lsp/runtime_test.exs
cd /Users/onurcansever/Desktop/phoenix-ls
npm test --workspace phoenix-pulse
npm test --workspace phoenix-pulse-nvim
```

Expected: explorer shows the controller-template-assign graph and existing sections continue to pass contract tests.

---

## Phase 10: Real Phoenix 1.8 App And Installed VSIX Dogfood

**Files:**
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/real_project_matrix_test.exs`
- Add fixture files under: `server/apps/phoenix_ls/test/fixtures/phoenix_1_8_complex_app`
- Modify: `packages/vscode-extension/scripts/dogfood-bundled-server.js`
- Modify: `packages/vscode-extension/scripts/dogfood-vscode.js`

- [ ] Create or regenerate a Phoenix 1.8 complex app with controllers, generated HTML, generated LiveView, auth, schemas, forms, uploads, hooks, colocated JS/CSS, routes, nested resources, and intentionally dynamic cases.
- [ ] Keep the generated fixture checked in only after trimming build artifacts, deps, `_build`, and node artifacts.
- [ ] Manual generation command for refresh:

```bash
tmp_root="$(mktemp -d /tmp/phoenix-ls-100pct.XXXXXX)"
mix phx.new "$tmp_root/pulse_complex" --database sqlite3
cd "$tmp_root/pulse_complex"
mix ecto.create
mix phx.gen.html Catalog Product products name:string sku:string price:decimal active:boolean
mix phx.gen.live Operations Order orders number:string status:string total:decimal
mix phx.gen.auth Accounts User users
mix deps.get
mix compile --warnings-as-errors
```

- [ ] Add custom complex examples manually after generation:
  - controller render keyword assigns
  - controller pipeline assigns
  - `render(assign(conn, :product, product), :show)`
  - `put_layout` and layout components
  - `start_async` and `handle_async`
  - `attach_hook`
  - `temporary_assigns`
  - upload UI
  - colocated hook
  - colocated CSS
  - nested `:for`, `:let`, and `inputs_for`
- [ ] Extend real project matrix minimums for controllers, uploads, hooks, colocated assets, and controller graph.
- [ ] Package and install the VSIX into an isolated VS Code profile:

```bash
npm run compile --workspace phoenix-pulse
npm run package:vscode
code --install-extension packages/vscode-extension/phoenix-pulse-*.vsix --force
npm run dogfood:server --workspace phoenix-pulse
npm run dogfood:vscode --workspace phoenix-pulse -- --fixture /tmp/phoenix-ls-100pct*/pulse_complex
```

- [ ] Manual VS Code/MCP checklist on the installed VSIX:
  - Problems panel has no false `phoenix.unknown_slot` errors in generated `show.html.heex`.
  - `.input` in `~H` completes attrs and hover shows attrs.
  - `<:` inside `<.header>` completes `:subtitle` and `:actions`.
  - `<:` inside `<.list>` completes `:item`.
  - `<:item ` completes required slot attrs.
  - Ctrl-hover and definition work for component attrs, slots, slot attrs, routes, templates, events, assigns, and controller assigns.
  - `phx-click`, `phx-submit`, `phx-hook`, `@uploads`, `JS.show`, and `~p` completions work in `.heex` and `~H`.
  - Explorer lists schemas, routes, templates, components, events, LiveViews, uploads, hooks, colocated assets, and controller graph.

Expected: installed VSIX behavior matches the unit/LSP tests in a real Phoenix 1.8 app.

---

## Phase 11: Old TypeScript Server Closure

**Files:**
- Create: `docs/old-ts-server-feature-closure.md`
- Delete: `packages/language-server`

- [ ] Map every captured old TypeScript test to one of: `implemented in v2`, `replaced by v2 design`, `intentional non-goal`, or `deferred post-100%`.
- [ ] Treat these as keepers:
  - controller-driven assign completions
  - special attr rich docs
  - component/slot rich docs and snippets
  - context-aware `phx-value-*`
  - element-aware Phoenix attr ranking
  - event-aware Phoenix attr ranking without noisy labeling
  - route helper completions
  - stream validation
  - template diagnostics
- [ ] Treat these as non-goals unless separately designed:
  - Emmet
  - generic HTML language-service behavior
  - generic Elixir completions beyond companion/full-mode fallback policy
  - regex parser fallback
- [ ] Run:

```bash
rg -n "implemented in v2|replaced by v2 design|intentional non-goal|deferred post-100%" docs/old-ts-server-feature-closure.md
```

Expected: no old TS behavior is silently forgotten, and the legacy workspace is absent.

---

## Phase 12: DRY, Size, Regex, And Performance Gates

**Files:**
- Modify only modules touched by earlier phases.
- Add tests only where a gate exposes an actual issue.

- [ ] Run large-file scan:

```bash
find server/apps/phoenix_ls/lib server/apps/phoenix_ls/test -name '*.ex' -o -name '*.exs' | xargs wc -l | sort -nr | head -30
```

- [ ] Split any newly-created production module over 350 lines unless the file is declarative metadata and has no behavior.
- [ ] Run duplicate/semantic regex scan:

```bash
rg -n "~r|Regex\\.|String\\.match\\?|String\\.replace|String\\.split|Code\\.string_to_quoted" server/apps/phoenix_ls/lib/phoenix_ls
```

- [ ] For every hit, verify it is non-semantic or already-parsed source utility. Semantic parsing must move to AST/HEEx/parser/scope modules.
- [ ] Run performance budgets after controller and lifecycle facts are added:

```bash
cd server/apps/phoenix_ls
mix test test/phoenix_ls/performance_budget_test.exs
```

- [ ] If budgets fail, optimize fact indexes and lookup helpers before adding caches. Any cache must have an owner and invalidation path.

Expected: no new giant modules, no duplicated doc builders, no semantic regex parsing, and no performance regression.

---

## Phase 13: Final Verification Gate

Run all commands from a clean-enough worktree after the preceding phases pass narrow tests:

```bash
cd /Users/onurcansever/Desktop/phoenix-ls/server/apps/phoenix_ls
mix format --check-formatted "lib/**/*.ex" "test/**/*.exs"
mix test
cd /Users/onurcansever/Desktop/phoenix-ls
npm run compile --workspace phoenix-pulse
npm test --workspace phoenix-pulse
npm test --workspace phoenix-pulse-nvim
npm run dogfood:server --workspace phoenix-pulse
npm run dogfood:vscode --workspace phoenix-pulse
npm run package:vscode
git diff --check
```

Then run the installed VSIX manual/MCP checklist from Phase 10 on the complex Phoenix 1.8 app.

Expected final evidence:

- Exact test counts from `mix test`, VS Code tests, and Neovim tests.
- Dogfood output paths and VSIX path.
- Generated app path.
- VS Code Problems panel result.
- A short list of any deliberate non-goals still present.

Only after this gate passes should the docs say Phoenix LS is 100% complete for the v2 companion scope.
