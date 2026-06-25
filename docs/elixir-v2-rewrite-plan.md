# Phoenix Pulse Elixir v2 Rewrite Plan

## Decision

Rewrite the language server as an Elixir-native LSP server.

This is a clean v2, not a line-by-line port of the current TypeScript implementation. The current TypeScript server is useful only as context for known pain, feature ideas, and mistakes to avoid. It is not a compatibility contract.

The VS Code extension remains TypeScript because VS Code extensions run in Node. The Neovim plugin remains Lua. Both editor integrations become thin launch/configuration layers around the Elixir server.

## Current Baseline

The current workspace has two editor product surfaces plus the Elixir server:

- `server/apps/phoenix_ls`: Elixir-native Phoenix LS server.
- `packages/vscode-extension`: VS Code extension that starts the Elixir server and provides extra UI.
- `packages/nvim-plugin`: Neovim plugin that starts the Elixir server and provides extra UI.

The former `packages/language-server` TypeScript server has been removed after
its user-facing behavior was captured in
`docs/old-ts-server-feature-closure.md`. Old TypeScript behavior remains
historical evidence only, not a parity contract.

Current server capabilities include:

- Incremental text document sync.
- Completion and completion resolve.
- Hover.
- Definition.
- Signature help.
- Code actions.
- Push diagnostics.
- Watched file handling.
- Phoenix custom requests:
  - `phoenix/listSchemas`
  - `phoenix/listComponents`
  - `phoenix/listRoutes`
  - `phoenix/listTemplates`
  - `phoenix/listEvents`
  - `phoenix/listLiveView`

## Rewrite Goals

1. Put Phoenix, HEEx, Mix, router, schema, LiveView, component, and template understanding in Elixir.
2. Remove the TypeScript server as the semantic core.
3. Avoid giant modules by separating LSP protocol, project indexing, parsing, storage, and features.
4. Make state ownership explicit through OTP processes.
5. Make cache invalidation testable and observable.
6. Support VS Code and Neovim from the same Elixir server.
7. Ship a smaller but solid v2 core before considering additional features.

## Non-Goals

- Do not port the current TypeScript files module-for-module.
- Do not preserve every current feature if it is poorly designed or low value.
- Do not make the VS Code extension itself Elixir.
- Do not introduce Go unless packaging proves impossible with Elixir.
- Do not use regex to parse Elixir, Phoenix, or HEEx semantics.
- Do not depend on full `Expert` as the PhoenixLS engine. Use it as an architecture reference.
- Do not preserve old TypeScript behavior for compatibility unless the v2 design independently justifies that behavior.

## Target Architecture

```text
phoenix_ls/
  mix.exs
  lib/
    phoenix_ls.ex
    phoenix_ls/application.ex

    phoenix_ls/lsp/
      server.ex
      transport/stdio.ex
      json_rpc.ex
      types.ex
      capabilities.ex
      dispatcher.ex

    phoenix_ls/workspace/
      supervisor.ex
      workspace.ex
      document_store.ex
      file_watcher.ex
      diagnostics_publisher.ex

    phoenix_ls/project/
      locator.ex
      mix_project.ex
      phoenix_detector.ex
      config_reader.ex

    phoenix_ls/index/
      supervisor.ex
      indexer.ex
      store.ex
      invalidation.ex
      snapshots.ex

    phoenix_ls/introspection/
      router.ex
      schema.ex
      component.ex
      live_view.ex
      template.ex
      controller.ex
      event.ex
      asset.ex

    phoenix_ls/parsing/
      elixir_ast.ex
      heex.ex
      source_map.ex
      cursor_context.ex

    phoenix_ls/features/
      completion.ex
      hover.ex
      definition.ex
      signature_help.ex
      code_action.ex
      diagnostics.ex
      phoenix_requests.ex

    phoenix_ls/features/completion/
      components.ex
      routes.ex
      schemas.ex
      forms.ex
      events.ex
      html.ex
      snippets.ex

    phoenix_ls/features/diagnostics/
      components.ex
      routes.ex
      templates.ex
      streams.ex
      navigation.ex
      comments.ex

    phoenix_ls/support/
      uri.ex
      positions.ex
      range.ex
      throttle.ex
      telemetry.ex
```

## Candidate Dependencies

Default choices:

- `gen_lsp`: primary LSP protocol and transport layer.
- Elixir standard library APIs: `Code.Fragment`, `Code.string_to_quoted/2`, `Macro`, `Mix`, `Path`, `File`, and OTP primitives.
- Phoenix and Phoenix LiveView APIs: project and HEEx understanding, isolated behind PhoenixLS adapters.
- `Sourceror`: source-preserving AST work, especially future code actions and safe edits.
- `file_system`: optional OS-level file watching when editor-sent file events are insufficient.
- `Burrito`: candidate for editor-friendly single-binary packaging.
- `ExUnit`: first-class test framework for protocol, parser, introspection, and fixture tests.

Conditional choices:

- `ElixirSense`: useful as a fallback for generic Elixir completion, hover, and definition. It should not own Phoenix-specific intelligence.
- `Jason`: only if the selected LSP layer does not already provide JSON encoding/decoding.
- `Telemetry`: use directly if `gen_lsp` integration is not enough for request timing, indexing events, and diagnostics publishing.

Rejected as default choices:

- Full `Expert` dependency: too broad for a Phoenix-specific server. Use its manager/engine split, indexing, GenLSP usage, and packaging approach as reference material.
- `elixir_lsp`: interesting protocol toolkit, but currently too young to choose over `gen_lsp` as the default.
- Hand-rolled LSP protocol implementation: only acceptable if `gen_lsp` blocks core requirements.
- Go/Rust core server: not the right default because Phoenix semantics still need Elixir.

## OTP Process Model

```text
PhoenixLS.Application
  PhoenixLS.LSP.Transport.Stdio
  PhoenixLS.LSP.Server
  PhoenixLS.Workspace.Supervisor
    PhoenixLS.Workspace.DocumentStore
    PhoenixLS.Workspace.FileWatcher
    PhoenixLS.Index.Supervisor
      PhoenixLS.Index.Indexer
      PhoenixLS.Index.Store
    PhoenixLS.Workspace.DiagnosticsPublisher
```

Responsibilities:

- `LSP.Server`: owns JSON-RPC lifecycle and request dispatch only.
- `DocumentStore`: owns open document text, versions, and URI/path conversion.
- `FileWatcher`: receives editor file-change events and optional OS watcher events.
- `Indexer`: schedules project scans and per-file reindex jobs.
- `Index.Store`: owns indexed facts, preferably ETS-backed behind a GenServer API.
- `DiagnosticsPublisher`: debounces diagnostics and pushes `textDocument/publishDiagnostics`.

Feature modules should be pure or mostly pure. They receive a request context plus a read-only project/index snapshot and return LSP response structs.

## Runtime Isolation

PhoenixLS should use a manager/engine split.

```text
Manager VM
  owns LSP transport, editor state, open documents, request routing, diagnostics publishing

Project Engine VM
  owns project compilation, Mix/Phoenix introspection, BEAM metadata, dependency loading, and project-side indexing
```

Reasons:

- Phoenix projects can define macros, config, aliases, and modules that should not pollute the language server runtime.
- User projects may depend on different Elixir, Erlang/OTP, Phoenix, and LiveView versions than PhoenixLS itself.
- Project compilation and introspection may crash or hang; failures should not take down the LSP transport.
- Multiple workspace folders should not share project runtime state accidentally.

The first skeleton may run manager and engine in one VM while protocol work is being proven, but the target architecture is separate manager and project engine processes.

Engine isolation requirements:

- use project-specific build/cache directories
- avoid loading project modules into the manager VM
- keep manager-owned structs stable across engine restarts
- make engine restart and reindex paths explicit
- support one engine per workspace root
- keep project-side dependencies minimal

## Compilation Strategy

PhoenixLS should support compilation-aware intelligence, but compilation must be isolated.

Compilation is needed because Phoenix and Elixir code commonly rely on macros, generated functions, compile-time configuration, Ecto schema macros, route macros, function component metadata, and LiveView conventions.

Rules:

- Do not compile user projects inside the manager VM.
- Do not write into the user's normal `_build` path by default.
- Use PhoenixLS-owned build/cache paths, for example `.phoenix_ls/build` or a user-cache directory keyed by project path and tool version.
- Keep Hex/Rebar/Mix caches isolated when building engine-side helper code.
- Prefer incremental document/file compilation after the initial project load.
- Fall back to source-only analysis when compilation is unavailable or unsafe.
- Treat project compilation as an engine capability, not as a requirement for basic server startup.

Compilation events should produce structured results:

- success
- warnings
- diagnostics
- stale index keys
- unavailable dependencies
- timeout/failure reason

No request handler should synchronously run full project compilation.

## Supported Versions

Define and test a support matrix before v2 replaces v1.

Initial target matrix:

- Elixir: current stable plus the oldest version needed by common Phoenix 1.7 projects.
- Erlang/OTP: versions compatible with the supported Elixir range.
- Phoenix: 1.7 and 1.8.
- Phoenix LiveView: versions used by Phoenix 1.7 and 1.8 projects.
- Project shapes:
  - normal Phoenix app
  - Phoenix app with colocated LiveViews/components
  - umbrella app
  - app with external function component modules
  - app with broken or incomplete syntax
  - app that does not currently compile

The exact version numbers should be locked in Phase 0 after checking current Phoenix/Elixir ecosystem versions and release constraints.

Compatibility matrix entries must include:

- supported
- best-effort
- explicitly unsupported
- not yet implemented

## Position and Source Mapping

LSP position correctness is a core requirement, not a detail.

PhoenixLS must handle:

- UTF-16 LSP positions
- UTF-8 Elixir strings
- graphemes and multibyte characters
- CRLF and LF line endings
- embedded Elixir inside HEEx
- `~H` sigil offsets inside `.ex` files
- `.heex` file offsets
- generated/derived metadata mapped back to source locations

Rules:

- All external LSP ranges use LSP UTF-16 positions.
- Internal parsing modules may use Elixir-native offsets, but conversions must happen through `PhoenixLS.Support.Positions` and `PhoenixLS.Parsing.SourceMap`.
- Source maps must be tested with Unicode, CRLF, HEEx tags, HEEx expressions, and `~H` sigils.
- Feature modules must not hand-roll line/column conversion.

## Request Flow

Example completion flow:

```text
Editor
  -> textDocument/completion
  -> LSP.Transport.Stdio
  -> LSP.Server
  -> LSP.Dispatcher
  -> Features.Completion
  -> Parsing.CursorContext
  -> Index.Store snapshot
  -> Completion-specific provider
  -> LSP response
```

Example file-change flow:

```text
Editor
  -> textDocument/didChange or workspace/didChangeWatchedFiles
  -> DocumentStore update
  -> Index.Invalidation marks affected files/facts stale
  -> Indexer schedules reindex
  -> DiagnosticsPublisher schedules affected diagnostics
```

## Data Model

Use explicit structs for indexed facts:

- `PhoenixLS.Introspection.Component`
- `PhoenixLS.Introspection.Component.Attribute`
- `PhoenixLS.Introspection.Component.Slot`
- `PhoenixLS.Introspection.Router.Route`
- `PhoenixLS.Introspection.Schema`
- `PhoenixLS.Introspection.Schema.Field`
- `PhoenixLS.Introspection.Template`
- `PhoenixLS.Introspection.Event`
- `PhoenixLS.Introspection.LiveView`

Each fact should include:

- stable ID
- source URI/path
- module name when applicable
- range/location
- extracted metadata
- source hash or mtime
- dependency keys for invalidation

Do not let raw maps spread through the codebase. Parse raw forms at boundaries, then convert into typed structs.

## Parsing Strategy

Use Elixir-native parsing first:

- `Code.string_to_quoted/2` or `Code.Fragment` where appropriate for Elixir source.
- `Phoenix.LiveView.HTMLTokenizer` / HEEx-related APIs where available and stable.
- Phoenix/Mix project conventions for locating routers, components, schemas, templates, controllers, assets, and config.
- `Sourceror` when source-preserving AST metadata is needed.

Keep parsing layers separate:

- `Parsing.ElixirAST`: syntax tree and module/function extraction.
- `Parsing.HEEx`: HEEx tokenization/tree extraction.
- `Parsing.CursorContext`: local editor context at a position.
- `Introspection.*`: Phoenix-specific meaning derived from parsed source.

The old `.exs` parser scripts should be mined for behavior but not copied as permanent scripts.

### Regex Policy

Regex is not allowed for semantic parsing.

Do not use regex to understand:

- Elixir module/function structure
- Phoenix routers
- Ecto schemas
- function components
- slots and attributes
- LiveView events
- HEEx tags, attributes, expressions, or sigils
- source locations used by LSP responses

Allowed regex use is limited to non-semantic utility work:

- simple filename or extension checks
- log filtering in tests
- small bounded validation of already-parsed strings
- compatibility shims where a parser API does not expose a needed lexical detail

Any allowed regex must be local, named, covered by tests, and must not be the source of truth for Phoenix/Elixir meaning.

### Regex Enforcement

The regex policy should be enforced mechanically.

Add a test or lint check that scans semantic directories for `Regex`, `~r`, and common regex entry points.

Restricted directories:

- `lib/phoenix_ls/parsing`
- `lib/phoenix_ls/introspection`
- `lib/phoenix_ls/features`

Allowed exceptions must be explicitly listed in a small allowlist with:

- file path
- function name
- reason
- tests proving the regex is non-semantic or only a compatibility shim

The allowlist should start empty.

## v2 Core Feature Scope

The first usable v2 should support:

- Server lifecycle:
  - `initialize`
  - `initialized`
  - `shutdown`
  - `exit`
  - text document open/change/close
  - watched file changes

- LSP features:
  - completion
  - completion resolve
  - hover
  - definition
  - diagnostics

- Phoenix intelligence:
  - component completions
  - component attribute completions
  - slot completions
  - verified route completions
  - router helper completions if still useful
  - schema/form field completions
  - LiveView event completions
  - basic Phoenix-specific diagnostics

- Custom Phoenix requests:
  - `phoenix/listSchemas`
  - `phoenix/listComponents`
  - `phoenix/listRoutes`
  - `phoenix/listTemplates`
  - `phoenix/listEvents`
  - `phoenix/listLiveView`

Signature help and code actions can be rebuilt after the core is stable unless they are needed for a specific editor release.

## Editor Integration

### VS Code

Keep `packages/vscode-extension` as a launcher for the Elixir server.

The extension should:

- locate the bundled or configured `phoenix_ls` executable
- start it over stdio
- pass initialization options
- keep existing Phoenix explorer UI where possible
- call the same custom `phoenix/*` requests

### Neovim

Keep `packages/nvim-plugin`.

The plugin should:

- configure `cmd = { "phoenix_ls" }`
- support custom server path override
- preserve project explorer and ERD UI only if the custom requests remain stable

## Packaging Options

Preferred sequence:

1. Start with a normal Mix project and executable `mix escript.build`.
2. Evaluate `burrito` or `mix release` for single-binary distribution.
3. Keep editor config supporting a custom server path during development.
4. Only consider Go/Rust wrappers if Elixir distribution becomes the blocking issue.

The package should not require every user to install the repo source. The final distribution needs an editor-friendly executable story.

## Security Model

PhoenixLS must treat the analyzed project as untrusted input.

Threats:

- project macros or config may execute code during compilation
- dependencies may run compile-time hooks
- project code may hang or consume excessive CPU/memory
- project code may define modules that collide with language-server modules
- workspace files may be malformed or intentionally adversarial

Rules:

- The manager VM must not load or execute project code.
- Project execution belongs only in the isolated engine VM.
- Engine crashes must be contained and reported as degraded project state.
- Long-running project operations must have timeouts.
- Logs must not include secrets from project config or environment variables.
- The server should expose a setting to disable project compilation and run source-only.
- Any future code action that writes files must be explicit and test-covered.

Open question for implementation planning: whether to prompt before compiling an untrusted workspace or default to source-only until the user opts in.

## Degraded Mode

The server should remain useful when parts of the project are unavailable.

Examples:

- Elixir executable is missing.
- Phoenix is not installed.
- dependencies are not fetched.
- project does not compile.
- current file has incomplete syntax.
- HEEx parser cannot parse a template.
- engine crashes or times out.
- index is stale or still warming up.

Expected behavior:

- LSP server stays alive.
- Basic document sync continues.
- Features degrade independently.
- Diagnostics explain unavailable capability when useful.
- Completion/hover/definition return partial results instead of crashing.
- Engine restart is attempted with backoff.
- Status is observable through logs and, if supported by the client, progress/status notifications.

Feature modules should return structured unavailable states instead of raising.

## Performance Budgets

Performance targets should be explicit and measured against fixture projects.

Initial budgets:

- completion from warm index: under 50 ms target, under 100 ms acceptable
- hover from warm index: under 50 ms target, under 100 ms acceptable
- definition from warm index: under 100 ms target
- diagnostics after edit: debounced, usually published within 250-750 ms
- no full project scan or compilation on keystroke
- initial indexing should report progress and avoid blocking editor interaction
- memory use should be tracked for small, medium, and large Phoenix fixtures

Phase 0 should define fixture sizes and exact acceptance thresholds.

Phase 6 should include stress checks for:

- large router files
- many components
- many schemas
- umbrella projects
- repeated rapid edits
- broken syntax during typing
- engine crash/restart loops

## Test Strategy

Testing is mandatory before replacing the current server.

Test layers:

- Parser unit tests with real Phoenix source snippets.
- Introspection tests using fixture Phoenix apps.
- Feature tests for completion, hover, definition, and diagnostics.
- LSP protocol tests over stdio using JSON-RPC messages.
- Contract tests for each v2 custom `phoenix/*` request.
- Regression tests for v2 behavior once implemented.

Suggested fixtures:

```text
test/fixtures/
  phoenix_1_7_app/
  phoenix_1_8_app/
  liveview_components_app/
  umbrella_app/
  broken_syntax_app/
```

## Implementation Phases

### Phase 0: v2 Scope and Risk Inventory

Produce a v2 feature and risk matrix:

- LSP method
- editor surface, if any
- v2 status: build now, later, or explicitly out of scope
- risk area
- required tests

The old TypeScript server may be inspected for feature ideas and failure modes, but this inventory must not become a parity checklist.

Output: `docs/elixir-v2-scope-matrix.md`.

### Phase 1: Elixir LSP Skeleton

Create a new Mix project for the server.

Deliverables:

- `gen_lsp`-based stdio transport
- initialize/shutdown lifecycle
- capability advertisement
- text document sync
- request dispatcher
- basic logging/telemetry
- protocol tests

### Phase 2: Workspace and Index Foundation

Build project discovery and indexing.

Deliverables:

- Mix project locator
- Phoenix project detector
- document store
- file watcher/event ingestion
- ETS-backed index store
- invalidation model
- fixture Phoenix apps

### Phase 3: Phoenix Introspection

Build native Elixir extraction.

Deliverables:

- router extraction
- schema extraction
- component extraction
- LiveView/event extraction
- template extraction
- source locations for all facts

### Phase 4: Core LSP Features

Build the first user-visible v2 feature set.

Deliverables:

- completions
- hover
- definition
- diagnostics
- completion resolve
- custom `phoenix/*` requests

### Phase 5: Editor Client Swap

Point VS Code and Neovim clients at the Elixir server.

Deliverables:

- VS Code launcher update
- Neovim launcher update
- custom server path config
- packaged executable lookup
- local editor QA checklist

### Phase 6: Hardening

Make it reliable enough to replace v1.

Deliverables:

- malformed file handling
- partial project handling
- large project performance checks
- debounce/throttle tuning
- crash recovery
- logs users can attach to bug reports

### Phase 7: Remove Legacy TypeScript Server

Remove the TypeScript language server package after v2 is ready to be the only server.

Keep the editor clients and docs.

## Architecture Rules

- No feature module over roughly 400 lines without a clear reason.
- No protocol handling inside feature providers.
- No filesystem scanning inside completion/hover/definition request handlers.
- No regex-based parsing for Elixir, Phoenix, or HEEx semantics.
- No hand-rolled LSP position conversion in feature modules.
- No raw JSON maps outside protocol boundary modules.
- No global process dictionary state.
- No long synchronous project-wide scans on keystroke.
- No project code loaded into the manager VM.
- Every cache must have an owner and invalidation path.
- Every indexed fact must know where it came from.

## Main Risks

### Elixir LSP Library Maturity

`gen_lsp` is the default LSP layer, but it is still less established than Node's `vscode-languageserver` ecosystem. We may need adapters, patches, or a small amount of isolated protocol code.

Mitigation: keep protocol code isolated under `PhoenixLS.LSP`, prototype lifecycle/document-sync/completion first, and keep hand-rolled protocol code behind adapter modules.

### Packaging

Node-based LSP servers are easy to publish through npm. Elixir executables need a deliberate distribution strategy.

Mitigation: support custom server paths first, then evaluate escript/release/single-binary packaging.

### HEEx API Stability

Some Phoenix/LiveView parsing APIs may be internal or version-sensitive.

Mitigation: isolate HEEx parsing behind `PhoenixLS.Parsing.HEEx` and test against multiple Phoenix/LiveView versions.

### Performance

Elixir can handle this well, but indexing must be incremental. A naive full-project scan on every edit would be worse than the current server.

Mitigation: explicit invalidation graph, debounced diagnostics, ETS snapshots, and background indexing.

### Legacy Coupling

Clean v2 may accidentally inherit old design assumptions or grow accidental parity requirements.

Mitigation: create a v2 scope matrix before implementation and mark each capability as build now, later, or explicitly out of scope.

## Recommended Next Step

Start with Phase 0 and Phase 1.

Do not begin by implementing completions. First create the v2 scope matrix and the Elixir LSP skeleton. Once lifecycle, document sync, request dispatch, and tests are stable, Phoenix-specific features can be added without turning the new server into another giant file.
