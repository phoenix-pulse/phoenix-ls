# Phoenix Pulse AGENTS.md

Project-specific instructions for this repository.

## Rewrite Direction

- This project is moving to a complete Elixir v2 rewrite of the language server.
- Do not optimize for migration from the current TypeScript language server.
- Do not treat current TypeScript behavior as a parity contract.
- Use old TypeScript code only to understand existing pain, user-facing ideas, and feature lessons.
- Prefer clean v2 architecture over preserving old public internals, file layout, or implementation habits.

## Core Architecture

- The language server core should be Elixir-native.
- VS Code remains TypeScript only as an editor launcher/client layer.
- Neovim remains Lua only as an editor launcher/client layer.
- Prefer `gen_lsp` for LSP protocol and transport.
- Use a manager/engine split for project isolation.
- Do not load or execute project code in the manager VM.
- Keep Phoenix, HEEx, Mix, router, schema, LiveView, component, and template intelligence in Elixir.

## Parsing Rules

- Do not use regex to parse Elixir, Phoenix, or HEEx semantics.
- Do not use regex for modules, functions, routers, schemas, components, slots, attributes, events, HEEx tags, HEEx expressions, sigils, or LSP source locations.
- Allowed regex use is limited to non-semantic utilities such as filename checks, test log filtering, or small validation of already-parsed strings.
- Any allowed regex must be local, named, tested, and documented with its reason.

## Code Shape

- Keep modules focused and small.
- Do not create giant server files.
- LSP protocol handling belongs in protocol/transport/dispatcher modules, not feature providers.
- Feature modules should be pure or mostly pure and receive explicit context.
- Every cache must have a clear owner and invalidation path.
- Every indexed fact must include source location and provenance.
- Do not hand-roll LSP UTF-16 position conversion inside feature modules.

## Testing And Verification

- Use ExUnit for the Elixir server.
- Prefer tests around parser behavior, source mapping, indexing, LSP request/response contracts, and degraded-mode behavior.
- Add failing tests before implementation for semantic features.
- Verify with narrow checks first.
- Do not claim behavior works without running the relevant check.

## Git And Scope

- Make the smallest safe change for the current rewrite step.
- Do not do drive-by refactors in the old TypeScript server.
- Do not push unless explicitly requested.
- Keep planning docs and agent instructions tracked even though this repository broadly ignores Markdown.
