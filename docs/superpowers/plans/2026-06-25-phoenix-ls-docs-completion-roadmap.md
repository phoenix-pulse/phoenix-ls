# Phoenix LS Docs Completion Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Phoenix LS v2 roadmap implied by `docs/phoenix-docs-lsp-feature-findings.md`, `docs/expert-companion-mode.md`, and `docs/elixir-v2-scope-matrix.md`.

**Architecture:** Keep Phoenix LS as a Phoenix, HEEx, and LiveView companion server for Expert. Add missing LiveView workflow intelligence as reusable facts first, then consume those facts from completion, hover, definition, diagnostics, code actions, and explorer payloads. Avoid feature-specific duplicate parsing by centralizing source extraction, facts, metadata, and diagnostic/code-action builders.

**Tech Stack:** Elixir, ExUnit, GenLSP, source-only AST/HEEx parsing, VS Code TypeScript launcher, Neovim Lua launcher.

---

## Non-Negotiable Design Rules

- Every new semantic concept starts as an indexed fact with source range and provenance.
- Feature providers consume facts; they do not parse source independently.
- Diagnostics and code actions are split by domain under `PhoenixLS.Features.Diagnostics.*` and `PhoenixLS.Features.CodeAction.*`.
- Reusable metadata belongs in focused modules such as `PhoenixLS.LiveView.Attributes`, `PhoenixLS.LiveView.Uploads`, and `PhoenixLS.LiveView.Hooks`.
- Request gating belongs in one policy module, not scattered across LSP handlers.
- No regex for Elixir, Phoenix, HEEx, router, schema, component, LiveView, or source-location semantics.
- Any JS/CSS scanning must be conservative, isolated, named, tested, and must not grow into a general JS/CSS language server.
- Each phase must run narrow tests first, then `mix format --check-formatted "lib/**/*.ex" "test/**/*.exs"`, `mix test`, and `git diff --check`.

## Completion Definition

Phoenix LS is complete for this roadmap when:

- Companion mode is implemented and tested for server policy plus VS Code/Neovim detection.
- Phoenix LS no longer returns generic Elixir fallback results in companion mode.
- Uploads, hooks, colocated JS/hooks/CSS, live navigation, deeper assigns, and focused HEEx structural diagnostics are implemented from shared facts.
- The three docs are updated to reflect implemented scope and remaining intentional non-goals.
- No production file grows into a new hotspot without a matching split.

---

## File Responsibility Map

### Existing Files To Extend Carefully

- `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server_config.ex`  
  Add resolved mode fields and companion settings. Do not mix request-policy logic here.

- `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`  
  Keep capabilities minimal. Do not advertise formatting, rename, references, workspace symbols, semantic tokens, or generic code actions.

- `server/apps/phoenix_ls/lib/phoenix_ls/lsp/{completion,hover,definition,diagnostics,code_action,signature_help}.ex`  
  Add calls into a policy module. Do not put mode branching directly into provider modules.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`  
  Keep as the LiveView traversal coordinator. Move upload/hook/assign extraction details into submodules if they exceed focused helper size.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`  
  Keep template fact extraction here, but colocated asset parsing should live in a colocated submodule.

- `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/phoenix.ex`  
  Aggregate completion modules only. Policy decides whether generic fallback is allowed.

- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics.ex`  
  Only orchestrates domain diagnostics. Add new diagnostics through small modules.

- `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action.ex`  
  Only dispatches Phoenix LS quick fixes. Add new quick fixes through small modules.

- `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests.ex`  
  Only dispatches explorer requests. Add upload/hook/asset explorer payloads through request modules.

### New Core Modules

- `server/apps/phoenix_ls/lib/phoenix_ls/features/policy.ex`  
  Central request ownership and companion-mode gating.

- `server/apps/phoenix_ls/lib/phoenix_ls/lsp/mode.ex`  
  Normalize `:auto | :companion | :full` mode based on user config and editor detection.

- `server/apps/phoenix_ls/lib/phoenix_ls/live_view/uploads.ex`  
  Upload metadata, allowed option names, helper functions, and shared validation predicates.

- `server/apps/phoenix_ls/lib/phoenix_ls/live_view/hooks.ex`  
  Hook naming rules, colocated hook naming rules, and shared hook value helpers.

- `server/apps/phoenix_ls/lib/phoenix_ls/live_view/navigation.ex`  
  Shared live navigation route classification and patch/navigate rules.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/uploads.ex`  
  Extract `allow_upload/3`, upload callbacks, and upload API references from LiveView AST.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/assigns.ex`  
  Extract assign facts from `assign/2`, `assign_new/3`, `update/3`, `stream/3`, `stream_insert/4`, and async assigns.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/uploads.ex`  
  Extract `@uploads`, `live_file_input/1`, `upload_errors/1/2`, and `phx-drop-target` usages from HEEx facts.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/hooks.ex`  
  Extract `phx-hook` usages from HEEx facts.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/colocated_assets.ex`  
  Extract colocated `<script>` and `<style>` blocks from HEEx document facts.

- `server/apps/phoenix_ls/lib/phoenix_ls/introspection/asset/hooks.ex`  
  Extract conservative hook facts from JS assets.

- `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/uploads.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/hooks.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/colocated_assets.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/uploads.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/hooks.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/colocated_assets.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/navigation.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/heex_structure.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/uploads.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/hooks.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/navigation.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/uploads.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/hooks.ex`
- `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/colocated_assets.ex`

---

## Phase 1: Companion Mode Policy

### Task 1.1: Server Mode Model

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/mode.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server_config.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_config_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/mode_test.exs`

- [ ] **Step 1: Add failing mode normalization tests**

Add tests covering:

```elixir
assert Mode.resolve(:auto, true) == :companion
assert Mode.resolve(:auto, false) == :full
assert Mode.resolve(:companion, false) == :companion
assert Mode.resolve(:full, true) == :full
```

Run:

```bash
mix test test/phoenix_ls/lsp/mode_test.exs
```

Expected: fail because `PhoenixLS.LSP.Mode` does not exist.

- [ ] **Step 2: Implement `PhoenixLS.LSP.Mode`**

Implement:

```elixir
defmodule PhoenixLS.LSP.Mode do
  @moduledoc """
  Resolves Phoenix LS runtime mode from user intent and editor detection.
  """

  @type mode :: :auto | :companion | :full
  @type resolved_mode :: :companion | :full

  @spec parse(term()) :: mode()
  def parse(value) when value in [:auto, :companion, :full], do: value
  def parse(value) when is_binary(value), do: value |> String.downcase() |> String.to_atom() |> parse()
  def parse(_value), do: :auto

  @spec resolve(mode(), boolean()) :: resolved_mode()
  def resolve(:auto, true), do: :companion
  def resolve(:auto, false), do: :full
  def resolve(:companion, _detected_expert?), do: :companion
  def resolve(:full, _detected_expert?), do: :full
end
```

- [ ] **Step 3: Extend `ServerConfig`**

Add fields:

```elixir
:mode,
:resolved_mode,
:detected_expert?,
:disable_generic_elixir?
```

Read env keys:

```text
PHOENIX_LS_MODE=auto|companion|full
PHOENIX_LS_DETECTED_EXPERT=true|false
PHOENIX_LS_DISABLE_GENERIC_ELIXIR=true|false
```

Default:

```elixir
mode: :auto,
resolved_mode: :full,
detected_expert?: false,
disable_generic_elixir?: true
```

- [ ] **Step 4: Verify**

Run:

```bash
mix test test/phoenix_ls/lsp/mode_test.exs test/phoenix_ls/lsp/server_config_test.exs
```

Expected: all tests pass.

### Task 1.2: Central Feature Policy

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/policy.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/policy_test.exs`

- [ ] **Step 1: Add failing policy tests**

Cover the matrix:

```elixir
assert Policy.allow?(:completion, :component_attr, companion_config())
refute Policy.allow?(:completion, :generic_elixir, companion_config())
assert Policy.allow?(:completion, :generic_elixir, full_config())
assert Policy.allow?(:hover, :route, companion_config())
refute Policy.allow?(:hover, :generic_elixir, companion_config())
assert Policy.allow?(:diagnostic, :phoenix, companion_config())
refute Policy.allow?(:diagnostic, :compiler, companion_config())
```

- [ ] **Step 2: Implement policy**

Use one public API:

```elixir
@spec allow?(atom(), atom(), PhoenixLS.LSP.ServerConfig.t()) :: boolean()
```

Rules:

- `:full` allows all implemented Phoenix LS providers.
- `:companion` allows `:phoenix`, `:component`, `:component_attr`, `:component_slot`, `:route`, `:schema`, `:template`, `:live_view`, `:upload`, `:hook`, `:colocated_asset`, `:navigation`, `:heex_structure`.
- `:companion` denies `:generic_elixir`, `:compiler`, `:formatting`, `:references`, `:rename`, `:workspace_symbol`.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/features/policy_test.exs
```

Expected: pass.

### Task 1.3: Gate Generic Fallback Completion

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/phoenix.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/completion.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/lsp/completion_transport_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/completion/phoenix_test.exs`

- [ ] **Step 1: Add failing companion completion tests**

Test ordinary expression completion in companion mode returns no `elixir_fallback` item. Test HEEx route/component completions still work.

- [ ] **Step 2: Thread config into completion aggregation**

Keep `ElixirFallback.complete/2` as a full-mode provider. Do not delete it. Add a policy-aware path:

```elixir
if Policy.allow?(:completion, :generic_elixir, config) do
  ElixirFallback.complete(context, facts)
else
  []
end
```

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/features/completion/phoenix_test.exs test/phoenix_ls/lsp/completion_transport_test.exs
```

Expected: pass.

### Task 1.4: Gate Hover, Definition, Diagnostics, Code Actions, Signature Help

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/hover.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/definition.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/diagnostics.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/code_action.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/signature_help.ex`
- Test: matching transport tests under `server/apps/phoenix_ls/test/phoenix_ls/lsp/`

- [ ] **Step 1: Add companion transport tests**

Add tests proving:

- component hover still works
- ordinary Elixir hover returns `nil`
- route definition still works
- ordinary Elixir definition returns `nil`
- only diagnostics with source `"PhoenixLS"` produce code actions
- signature help is empty outside Phoenix/HEEx/router/schema contexts

- [ ] **Step 2: Implement gating through `Policy`**

Handlers should classify request context and call `Policy.allow?/3`. Do not add ad-hoc `if companion` checks inside feature modules.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/lsp/hover_transport_test.exs test/phoenix_ls/lsp/definition_transport_test.exs test/phoenix_ls/lsp/diagnostics_transport_test.exs test/phoenix_ls/lsp/code_action_transport_test.exs test/phoenix_ls/lsp/signature_help_transport_test.exs
```

Expected: pass.

---

## Phase 2: Editor Companion Detection

### Task 2.1: VS Code Settings And Expert Detection

**Files:**
- Modify: `packages/vscode-extension/package.json`
- Modify: `packages/vscode-extension/src/extension.ts`
- Test: existing VS Code extension tests or new focused test under `packages/vscode-extension/src/`

- [ ] **Step 1: Add settings**

Add settings:

```json
"phoenixLS.mode": {
  "type": "string",
  "enum": ["auto", "companion", "full"],
  "default": "auto"
},
"phoenixLS.companion.detectExpert": {
  "type": "boolean",
  "default": true
},
"phoenixLS.companion.disableGenericElixir": {
  "type": "boolean",
  "default": true
}
```

- [ ] **Step 2: Detect Expert**

Detect installed/enabled extension id `ExpertLSP.expert`. Pass env:

```text
PHOENIX_LS_MODE
PHOENIX_LS_DETECTED_EXPERT
PHOENIX_LS_DISABLE_GENERIC_ELIXIR
```

- [ ] **Step 3: Log resolved mode**

Write one output-channel line:

```text
Phoenix LS mode: companion (Expert detected)
```

No modal notification.

- [ ] **Step 4: Verify**

Run:

```bash
npm run compile --workspace phoenix-pulse
npm test --workspace phoenix-pulse
```

Expected: pass.

### Task 2.2: Neovim Mode Settings

**Files:**
- Modify: `packages/nvim-plugin/lua/phoenix-pulse/init.lua`
- Modify: `packages/nvim-plugin/lua/phoenix-pulse/lsp.lua`
- Test: existing or new nvim plugin tests

- [ ] **Step 1: Add setup options**

Expose:

```lua
mode = "auto"
companion = {
  detect_expert = true,
  disable_generic_elixir = true,
}
```

- [ ] **Step 2: Detect Expert**

Detect active or configured `expert` LSP client. Explicit user mode overrides detection.

- [ ] **Step 3: Pass env to server**

Pass the same env variables as VS Code.

- [ ] **Step 4: Verify**

Run:

```bash
npm test --workspace phoenix-pulse-nvim
```

Expected: pass.

---

## Phase 3: Upload Intelligence

### Task 3.1: Upload Fact Extraction

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/live_view/uploads.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/uploads.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`

- [ ] **Step 1: Add failing tests for upload facts**

Fixture:

```elixir
def mount(_params, _session, socket) do
  {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
end
```

Expected fact:

```elixir
%Fact{
  kind: :upload,
  data: %{
    module: "AppWeb.ProfileLive",
    name: "avatar",
    options: [accept: [".jpg", ".png"], max_entries: 1]
  }
}
```

- [ ] **Step 2: Implement upload extraction**

Extract only static atom/string upload names. Store source range at the upload name when available, otherwise the call range.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/introspection/live_view_test.exs
```

Expected: pass.

### Task 3.2: Upload HEEx Usage Facts

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/uploads.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`

- [ ] **Step 1: Add failing tests**

Cover facts for:

- `@uploads.avatar`
- `<.live_file_input upload={@uploads.avatar} />`
- `upload_errors(@uploads.avatar)`
- `phx-drop-target={@uploads.avatar.ref}`

- [ ] **Step 2: Implement usage extraction from parsed HEEx document**

Use `PhoenixLS.HEEx.Document` nodes and existing source ranges. Do not parse HEEx with regex.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/introspection/template_test.exs
```

Expected: pass.

### Task 3.3: Upload Completion, Diagnostics, Code Actions, Explorer

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/uploads.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/uploads.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/uploads.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/uploads.ex`
- Modify orchestrators for completion, diagnostics, code actions, and requests
- Test: completion, diagnostics, code action, phoenix request tests

- [ ] **Step 1: Add failing feature tests**

Cover:

- complete `@uploads.avatar`
- diagnose unknown upload name in `live_file_input`
- diagnose upload form missing `phx-change`
- diagnose upload form missing `phx-submit`
- code action adds missing upload form binding
- explorer request returns upload list

- [ ] **Step 2: Implement providers from upload facts only**

No provider should scan raw source. Providers consume `:upload` and upload usage facts.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/features/completion test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/code_action_test.exs test/phoenix_ls/features/phoenix_requests_test.exs
```

Expected: pass.

---

## Phase 4: Hook Intelligence

### Task 4.1: Hook Facts From Assets And HEEx

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/live_view/hooks.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/asset/hooks.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/hooks.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/asset.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/asset_test.exs`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/template_test.exs`

- [ ] **Step 1: Add failing hook extraction tests**

Asset fixture:

```javascript
let Hooks = {}
Hooks.PhoneNumber = {
  mounted() {}
}
```

HEEx fixture:

```heex
<div id="phone" phx-hook="PhoneNumber"></div>
```

Expected facts:

- `:hook` with name `PhoneNumber`
- `:hook_usage` with name `PhoneNumber`

- [ ] **Step 2: Implement conservative JS hook extraction**

Use a small isolated scanner in `Introspection.Asset.Hooks`. It may only recognize tested hook map patterns. It must not be reused for Elixir/Phoenix/HEEx semantics.

- [ ] **Step 3: Implement HEEx `phx-hook` usage extraction**

Use parsed HEEx attributes and literal values.

- [ ] **Step 4: Verify**

Run:

```bash
mix test test/phoenix_ls/introspection/asset_test.exs test/phoenix_ls/introspection/template_test.exs
```

Expected: pass.

### Task 4.2: Hook Completion, Diagnostics, Definition, Explorer

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/hooks.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/hooks.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/hooks.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/hooks.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/definition.ex`

- [ ] **Step 1: Add failing feature tests**

Cover:

- complete literal hook names in `phx-hook`
- diagnose unknown literal hook names
- definition from `phx-hook="PhoneNumber"` to JS hook fact
- explorer request lists hooks

- [ ] **Step 2: Implement providers from facts**

Use `PhoenixLS.LiveView.Hooks` for naming rules. Do not duplicate hook name validation in completion and diagnostics.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/features/completion test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/definition_test.exs test/phoenix_ls/features/phoenix_requests_test.exs
```

Expected: pass.

---

## Phase 5: Colocated JS, Hooks, And CSS

### Task 5.1: Colocated Asset Facts

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template/colocated_assets.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/completion/colocated_assets.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/colocated_assets.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/phoenix_requests/colocated_assets.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/template.ex`

- [ ] **Step 1: Add failing extraction tests**

Cover HEEx blocks:

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
  export default {}
</script>

<script :type={Phoenix.LiveView.ColocatedJS}>
  console.log("local")
</script>

<style :type={Phoenix.LiveView.ColocatedCSS}>
  .root {}
</style>
```

Expected facts:

- `:colocated_hook`
- `:colocated_js`
- `:colocated_css`

- [ ] **Step 2: Implement extraction**

Use HEEx parser output. Fact data must include owner module when known, generated name when known, source range, and options.

- [ ] **Step 3: Add completion and diagnostics**

Complete valid colocated `:type` module names. Diagnose invalid colocated hook names using `PhoenixLS.LiveView.Hooks`.

- [ ] **Step 4: Add explorer payloads**

Expose colocated assets grouped by owner module.

- [ ] **Step 5: Verify**

Run:

```bash
mix test test/phoenix_ls/introspection/template_test.exs test/phoenix_ls/features/completion test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/phoenix_requests_test.exs
```

Expected: pass.

---

## Phase 6: Live Navigation Diagnostics

### Task 6.1: Navigation Classification

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/live_view/navigation.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/navigation.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action/navigation.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/code_action.ex`

- [ ] **Step 1: Add failing diagnostics tests**

Cover:

- `patch={~p"/other-live"}` from a different LiveView warns
- `navigate={~p"/different-session"}` warns when live session changes
- `push_patch(socket, to: ~p"/other-live")` warns
- patch navigation without `handle_params/3` suggests adding callback

- [ ] **Step 2: Implement route classification**

Use route facts, live module, action, and live session. Do not duplicate route helper parsing.

- [ ] **Step 3: Implement diagnostics and quick fixes**

Diagnostics use source `"PhoenixLS"` and stable codes:

- `phoenix.invalid_live_patch`
- `phoenix.invalid_live_navigate`
- `phoenix.missing_handle_params`

- [ ] **Step 4: Verify**

Run:

```bash
mix test test/phoenix_ls/features/diagnostics_test.exs test/phoenix_ls/features/code_action_test.exs
```

Expected: pass.

---

## Phase 7: Deeper Assign Extraction

### Task 7.1: Assign Fact Expansion

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view/assigns.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/introspection/live_view.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/introspection/live_view_test.exs`

- [ ] **Step 1: Add failing tests**

Cover assign names from:

- `assign(socket, name: value, count: count)`
- `assign_new(socket, :current_user, fn -> nil end)`
- `update(socket, :count, &(&1 + 1))`
- `stream(socket, :messages, messages)`
- `assign_async(socket, :stats, fn -> {:ok, %{stats: %{}}} end)`

- [ ] **Step 2: Implement extraction**

Emit `:assign` facts for static assign names. Add `source` metadata such as `:assign`, `:assign_new`, `:update`, `:stream`, `:assign_async`.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/introspection/live_view_test.exs test/phoenix_ls/features/completion
```

Expected: pass.

---

## Phase 8: Focused HEEx Structural Diagnostics

### Task 8.1: High-Signal HEEx Structure Checks

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics/heex_structure.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/features/diagnostics.ex`
- Test: `server/apps/phoenix_ls/test/phoenix_ls/features/diagnostics_test.exs`

- [ ] **Step 1: Add failing tests**

Cover only high-signal checks:

- mismatched closing tag
- duplicate literal attr
- void element with child content
- unclosed tag if parser exposes a reliable range

- [ ] **Step 2: Implement checks from HEEx document model**

Use `PhoenixLS.HEEx.Document`. Do not compete with compiler diagnostics when source range confidence is poor.

- [ ] **Step 3: Verify**

Run:

```bash
mix test test/phoenix_ls/features/diagnostics_test.exs
```

Expected: pass.

---

## Phase 9: Docs And Scope Matrix Refresh

### Task 9.1: Update Roadmap Docs

**Files:**
- Modify: `docs/phoenix-docs-lsp-feature-findings.md`
- Modify: `docs/expert-companion-mode.md`
- Modify: `docs/elixir-v2-scope-matrix.md`

- [ ] **Step 1: Update implementation references**

Replace stale references to monolithic modules with split modules:

- diagnostics domain modules
- code action domain modules
- Phoenix request payload modules
- router path/resource helpers

- [ ] **Step 2: Update status values**

Move completed items from `later` to completed notes only after implementation and tests pass.

- [ ] **Step 3: Preserve non-goals**

Keep these explicitly out of scope:

- Expert replacement
- generic Elixir parity
- generic JS/CSS language server behavior
- broad Ecto query analysis
- semantic regex parsing

- [ ] **Step 4: Verify docs and code**

Run:

```bash
mix format --check-formatted "lib/**/*.ex" "test/**/*.exs"
mix test
git diff --check
```

Expected: all pass.

---

## Phase 10: Full Completion Gate

### Task 10.1: Real Project Matrix Expansion

**Files:**
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/real_project_matrix_test.exs`
- Modify or create fixture helpers under existing fixture support

- [ ] **Step 1: Add real-world fixture coverage**

Add fixtures for:

- LiveView upload form
- asset hook registration
- colocated hook/js/css
- live navigation across same and different live sessions
- assign_async and stream usage

- [ ] **Step 2: Verify feature behavior on fixtures**

Assert facts, diagnostics, completions, and explorer payloads remain correct under project-indexed mode.

- [ ] **Step 3: Final verification**

Run:

```bash
mix format --check-formatted "lib/**/*.ex" "test/**/*.exs"
mix test
npm run compile --workspace phoenix-pulse
npm test --workspace phoenix-pulse
npm test --workspace phoenix-pulse-nvim
npm run dogfood:server --workspace phoenix-pulse
npm run dogfood:vscode --workspace phoenix-pulse
git diff --check
```

Expected: all pass.

---

## Recommended Execution Order

1. Phase 1: Companion mode policy.
2. Phase 2: Editor detection.
3. Phase 3: Upload intelligence.
4. Phase 4: Hook intelligence.
5. Phase 5: Colocated asset support.
6. Phase 6: Live navigation diagnostics.
7. Phase 7: Deeper assign extraction.
8. Phase 8: Focused HEEx structural diagnostics.
9. Phase 9: Docs refresh.
10. Phase 10: Real project matrix and dogfood gate.

## Commit Strategy

Use one commit per phase, or split large feature phases into:

- fact extraction
- completion/definition/explorer
- diagnostics/code actions
- docs/tests

Do not mix unrelated phases in one commit.

## Self-Review Checklist

- Companion behavior is centralized in `PhoenixLS.Features.Policy`.
- Uploads, hooks, colocated assets, navigation, assigns, and HEEx structure each have one owner module for shared semantics.
- Completion, diagnostics, code actions, and explorer modules consume facts instead of parsing.
- No provider duplicates fact lookup or route/helper/upload/hook semantics.
- New facts include range and provenance.
- No semantic regex parsing for Elixir/Phoenix/HEEx.
- Every phase has focused tests and full verification.
