# Elixir v2 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first clean Elixir-native PhoenixLS foundation with no TypeScript migration/parity requirement.

**Architecture:** Create a new Elixir umbrella under `server/` with a focused `:phoenix_ls` manager application. The first milestone proves project structure, GenLSP lifecycle shape, document storage, UTF-16 position conversion, regex enforcement, and v2 scope documentation before Phoenix-specific intelligence is added.

**Tech Stack:** Elixir, OTP, ExUnit, GenLSP, Sourceror, file_system, Burrito later for packaging.

---

## Scope Boundary

This plan intentionally does not migrate old TypeScript code. The current TypeScript server is not a parity contract. It may be inspected only for lessons, known fragile areas, and feature ideas.

This plan stops before router/schema/component/HEEx intelligence. Those features require a separate plan after the foundation is green.

## File Structure

- Create `server/mix.exs`: umbrella Mix project.
- Create `server/.formatter.exs`: formatter config for umbrella apps.
- Create `server/apps/phoenix_ls/mix.exs`: manager application Mix project.
- Create `server/apps/phoenix_ls/lib/phoenix_ls.ex`: public application namespace.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`: OTP application supervisor.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`: server capability builder.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`: GenLSP callback module for lifecycle skeleton.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document.ex`: open document struct and text update helpers.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document_store.ex`: GenServer owner for open documents.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/support/positions.ex`: UTF-16/LSP position conversion utilities.
- Create `server/apps/phoenix_ls/test/test_helper.exs`: ExUnit bootstrap.
- Create `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`: application smoke tests.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`: capability tests.
- Create `server/apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`: document store tests.
- Create `server/apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs`: UTF-16 position tests.
- Create `server/apps/phoenix_ls/test/phoenix_ls/architecture/regex_policy_test.exs`: semantic regex enforcement.
- Create `docs/elixir-v2-scope-matrix.md`: initial v2-only scope matrix.

## Task 1: Create Elixir Umbrella Skeleton

**Files:**
- Create: `server/mix.exs`
- Create: `server/.formatter.exs`
- Create: `server/apps/phoenix_ls/mix.exs`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`
- Create: `server/apps/phoenix_ls/test/test_helper.exs`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`

- [ ] **Step 1: Write the failing application smoke test**

Create `server/apps/phoenix_ls/test/test_helper.exs`:

```elixir
ExUnit.start()
```

Create `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`:

```elixir
defmodule PhoenixLS.ApplicationTest do
  use ExUnit.Case, async: true

  test "application module exposes the OTP child specification" do
    assert PhoenixLS.Application.child_spec([]).id == PhoenixLS.Application
  end

  test "public namespace exposes a version string" do
    assert PhoenixLS.version() == "0.1.0"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/application_test.exs
```

Expected: FAIL because `server/mix.exs` and the `PhoenixLS` modules do not exist yet.

- [ ] **Step 3: Create the umbrella Mix project**

Create `server/mix.exs`:

```elixir
defmodule PhoenixLS.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
```

Create `server/.formatter.exs`:

```elixir
[
  inputs: [
    "mix.exs",
    "apps/*/{mix,.formatter}.exs",
    "apps/*/{config,lib,test}/**/*.{ex,exs}"
  ]
]
```

- [ ] **Step 4: Create the PhoenixLS manager application**

Create `server/apps/phoenix_ls/mix.exs`:

```elixir
defmodule PhoenixLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_ls,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PhoenixLS.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gen_lsp, "~> 0.11"},
      {:sourceror, "~> 1.12", only: [:dev, :test]},
      {:file_system, "~> 1.1", optional: true}
    ]
  end
end
```

Create `server/apps/phoenix_ls/lib/phoenix_ls.ex`:

```elixir
defmodule PhoenixLS do
  @moduledoc """
  PhoenixLS is the Elixir-native Phoenix language server.
  """

  @version "0.1.0"

  def version, do: @version
end
```

Create `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`:

```elixir
defmodule PhoenixLS.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: PhoenixLS.Supervisor
    )
  end
end
```

- [ ] **Step 5: Fetch dependencies and run the smoke test**

Run:

```bash
cd server && mix deps.get
cd server && mix test apps/phoenix_ls/test/phoenix_ls/application_test.exs
```

Expected: PASS for both tests.

- [ ] **Step 6: Commit**

Run:

```bash
git add AGENTS.md .gitignore docs/elixir-v2-rewrite-plan.md docs/superpowers/plans/2026-06-24-elixir-v2-foundation.md server/mix.exs server/.formatter.exs server/apps/phoenix_ls/mix.exs server/apps/phoenix_ls/lib/phoenix_ls.ex server/apps/phoenix_ls/lib/phoenix_ls/application.ex server/apps/phoenix_ls/test/test_helper.exs server/apps/phoenix_ls/test/phoenix_ls/application_test.exs
git commit -m "chore: start elixir v2 language server foundation"
```

Expected: local commit succeeds. Do not push.

## Task 2: Add LSP Capability Builder

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`

- [ ] **Step 1: Write the failing capability tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs`:

```elixir
defmodule PhoenixLS.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.Capabilities

  test "advertises incremental text sync and core v2 features" do
    capabilities = Capabilities.build()

    assert capabilities.text_document_sync.open_close == true
    assert capabilities.text_document_sync.change != nil
    assert capabilities.completion_provider.resolve_provider == true
    assert capabilities.hover_provider == true
    assert capabilities.definition_provider == true
  end

  test "completion trigger characters include Phoenix and HEEx contexts" do
    capabilities = Capabilities.build()

    assert "<" in capabilities.completion_provider.trigger_characters
    assert "@" in capabilities.completion_provider.trigger_characters
    assert "." in capabilities.completion_provider.trigger_characters
    assert "{" in capabilities.completion_provider.trigger_characters
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs
```

Expected: FAIL because `PhoenixLS.LSP.Capabilities` does not exist.

- [ ] **Step 3: Implement the capability builder**

Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex`:

```elixir
defmodule PhoenixLS.LSP.Capabilities do
  @moduledoc """
  Builds LSP server capabilities for the clean v2 server.
  """

  alias GenLSP.Enumerations.TextDocumentSyncKind

  alias GenLSP.Structures.{
    CompletionOptions,
    ServerCapabilities,
    TextDocumentSyncOptions
  }

  @trigger_characters ["<", " ", "-", ":", "\"", "=", "{", ".", "#", "@"]

  def build do
    %ServerCapabilities{
      text_document_sync: %TextDocumentSyncOptions{
        open_close: true,
        change: TextDocumentSyncKind.incremental()
      },
      completion_provider: %CompletionOptions{
        resolve_provider: true,
        trigger_characters: @trigger_characters
      },
      hover_provider: true,
      definition_provider: true
    }
  end
end
```

- [ ] **Step 4: Run the capability tests**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs
```

Expected: PASS. If GenLSP struct names differ, inspect `deps/gen_lsp/lib` and adjust this module only; do not leak protocol maps into feature code.

- [ ] **Step 5: Commit**

Run:

```bash
git add server/apps/phoenix_ls/lib/phoenix_ls/lsp/capabilities.ex server/apps/phoenix_ls/test/phoenix_ls/lsp/capabilities_test.exs
git commit -m "feat: define elixir v2 lsp capabilities"
```

Expected: local commit succeeds. Do not push.

## Task 3: Add GenLSP Lifecycle Skeleton

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`

- [ ] **Step 1: Write the failing lifecycle tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`:

```elixir
defmodule PhoenixLS.LSP.ServerLifecycleTest do
  use ExUnit.Case, async: true

  alias GenLSP.Requests.Initialize
  alias GenLSP.Structures.InitializeParams
  alias PhoenixLS.LSP.Server

  test "initialize returns PhoenixLS server info and capabilities" do
    params = %InitializeParams{
      process_id: nil,
      root_uri: "file:///tmp/example"
    }

    request = %Initialize{id: 1, params: params}
    lsp = Server.initial_state([])

    assert {:reply, result, updated_lsp} = Server.handle_request(request, lsp)
    assert result.server_info.name == "PhoenixLS"
    assert result.server_info.version == PhoenixLS.version()
    assert result.capabilities.hover_provider == true
    assert updated_lsp.assigns.root_uri == "file:///tmp/example"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: FAIL because `PhoenixLS.LSP.Server` does not exist.

- [ ] **Step 3: Implement the lifecycle skeleton**

Create `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`:

```elixir
defmodule PhoenixLS.LSP.Server do
  @moduledoc """
  GenLSP callback module for PhoenixLS.

  This module owns LSP lifecycle dispatch only. Phoenix feature logic belongs in
  `PhoenixLS.Features.*` modules.
  """

  use GenLSP

  alias GenLSP.Requests.{Initialize, Shutdown}
  alias GenLSP.Structures.{InitializeParams, InitializeResult}
  alias PhoenixLS.LSP.Capabilities

  def start_link(args) do
    GenLSP.start_link(__MODULE__, args, [])
  end

  def initial_state(args) do
    {:ok, lsp} = init(%{}, args)
    lsp
  end

  @impl true
  def init(lsp, _args) do
    {:ok, assign(lsp, exit_code: 1, root_uri: nil)}
  end

  @impl true
  def handle_request(%Initialize{params: %InitializeParams{root_uri: root_uri}}, lsp) do
    result = %InitializeResult{
      capabilities: Capabilities.build(),
      server_info: %{name: "PhoenixLS", version: PhoenixLS.version()}
    }

    {:reply, result, assign(lsp, root_uri: root_uri)}
  end

  @impl true
  def handle_request(%Shutdown{}, lsp) do
    {:noreply, assign(lsp, exit_code: 0)}
  end
end
```

- [ ] **Step 4: Run the lifecycle test**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: PASS. If GenLSP test setup requires a real GenLSP state struct, create a small `PhoenixLS.LSP.ServerTestHarness` in test support instead of changing production design.

- [ ] **Step 5: Commit**

Run:

```bash
git add server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
git commit -m "feat: add gen_lsp lifecycle skeleton"
```

Expected: local commit succeeds. Do not push.

## Task 4: Add Document Store

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document_store.ex`
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`

- [ ] **Step 1: Write the failing document store tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs`:

```elixir
defmodule PhoenixLS.Workspace.DocumentStoreTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Workspace.DocumentStore

  test "opens, fetches, changes, and closes a document" do
    start_supervised!({DocumentStore, name: __MODULE__.Store})

    uri = "file:///tmp/page.html.heex"

    assert :ok = DocumentStore.open(__MODULE__.Store, uri, "heex", 1, "hello")
    assert {:ok, doc} = DocumentStore.fetch(__MODULE__.Store, uri)
    assert doc.uri == uri
    assert doc.language_id == "heex"
    assert doc.version == 1
    assert doc.text == "hello"

    assert :ok = DocumentStore.replace(__MODULE__.Store, uri, 2, "hello world")
    assert {:ok, updated} = DocumentStore.fetch(__MODULE__.Store, uri)
    assert updated.version == 2
    assert updated.text == "hello world"

    assert :ok = DocumentStore.close(__MODULE__.Store, uri)
    assert :error = DocumentStore.fetch(__MODULE__.Store, uri)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs
```

Expected: FAIL because document modules do not exist.

- [ ] **Step 3: Implement document struct**

Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document.ex`:

```elixir
defmodule PhoenixLS.Workspace.Document do
  @moduledoc """
  Open editor document tracked by PhoenixLS.
  """

  @enforce_keys [:uri, :language_id, :version, :text]
  defstruct [:uri, :language_id, :version, :text]

  def new(uri, language_id, version, text) do
    %__MODULE__{
      uri: uri,
      language_id: language_id,
      version: version,
      text: text
    }
  end

  def replace(%__MODULE__{} = document, version, text) do
    %{document | version: version, text: text}
  end
end
```

- [ ] **Step 4: Implement document store**

Create `server/apps/phoenix_ls/lib/phoenix_ls/workspace/document_store.ex`:

```elixir
defmodule PhoenixLS.Workspace.DocumentStore do
  @moduledoc """
  Owns open editor documents.
  """

  use GenServer

  alias PhoenixLS.Workspace.Document

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def open(server \\ __MODULE__, uri, language_id, version, text) do
    GenServer.call(server, {:open, uri, language_id, version, text})
  end

  def replace(server \\ __MODULE__, uri, version, text) do
    GenServer.call(server, {:replace, uri, version, text})
  end

  def fetch(server \\ __MODULE__, uri) do
    GenServer.call(server, {:fetch, uri})
  end

  def close(server \\ __MODULE__, uri) do
    GenServer.call(server, {:close, uri})
  end

  @impl true
  def init(documents), do: {:ok, documents}

  @impl true
  def handle_call({:open, uri, language_id, version, text}, _from, documents) do
    document = Document.new(uri, language_id, version, text)
    {:reply, :ok, Map.put(documents, uri, document)}
  end

  def handle_call({:replace, uri, version, text}, _from, documents) do
    documents =
      Map.update!(documents, uri, fn document ->
        Document.replace(document, version, text)
      end)

    {:reply, :ok, documents}
  end

  def handle_call({:fetch, uri}, _from, documents) do
    {:reply, Map.fetch(documents, uri), documents}
  end

  def handle_call({:close, uri}, _from, documents) do
    {:reply, :ok, Map.delete(documents, uri)}
  end
end
```

- [ ] **Step 5: Supervise the document store**

Modify `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`:

```elixir
defmodule PhoenixLS.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixLS.Workspace.DocumentStore
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: PhoenixLS.Supervisor
    )
  end
end
```

- [ ] **Step 6: Run the document store tests**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add server/apps/phoenix_ls/lib/phoenix_ls/workspace/document.ex server/apps/phoenix_ls/lib/phoenix_ls/workspace/document_store.ex server/apps/phoenix_ls/lib/phoenix_ls/application.ex server/apps/phoenix_ls/test/phoenix_ls/workspace/document_store_test.exs
git commit -m "feat: add open document store"
```

Expected: local commit succeeds. Do not push.

## Task 5: Add UTF-16 LSP Position Utilities

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/support/positions.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs`

- [ ] **Step 1: Write failing Unicode position tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs`:

```elixir
defmodule PhoenixLS.Support.PositionsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Support.Positions

  test "converts zero-based LSP line and UTF-16 character to byte offset" do
    text = "abc\nhello"

    assert Positions.lsp_position_to_offset(text, %{line: 1, character: 2}) == {:ok, 6}
  end

  test "counts astral codepoints as two UTF-16 code units" do
    text = "a😀b"

    assert Positions.lsp_position_to_offset(text, %{line: 0, character: 3}) == {:ok, byte_size("a😀")}
    assert Positions.offset_to_lsp_position(text, byte_size("a😀")) == {:ok, %{line: 0, character: 3}}
  end

  test "handles CRLF line endings" do
    text = "one\r\ntwo"

    assert Positions.lsp_position_to_offset(text, %{line: 1, character: 0}) == {:ok, byte_size("one\r\n")}
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs
```

Expected: FAIL because `PhoenixLS.Support.Positions` does not exist.

- [ ] **Step 3: Implement position conversion**

Create `server/apps/phoenix_ls/lib/phoenix_ls/support/positions.ex`:

```elixir
defmodule PhoenixLS.Support.Positions do
  @moduledoc """
  Converts between LSP UTF-16 positions and Elixir byte offsets.
  """

  def lsp_position_to_offset(text, %{line: target_line, character: target_character})
      when is_binary(text) and target_line >= 0 and target_character >= 0 do
    text
    |> split_lines_with_endings()
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {line, line_index}, offset ->
      cond do
        line_index < target_line ->
          {:cont, offset + byte_size(line)}

        line_index == target_line ->
          case utf16_character_to_line_offset(line, target_character) do
            {:ok, line_offset} -> {:halt, {:ok, offset + line_offset}}
            :error -> {:halt, :error}
          end

        true ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, _offset} = result -> result
      :error -> :error
      offset when target_line == 0 and text == "" and target_character == 0 -> {:ok, offset}
      _offset -> :error
    end
  end

  def offset_to_lsp_position(text, target_offset)
      when is_binary(text) and target_offset >= 0 and target_offset <= byte_size(text) do
    text
    |> split_lines_with_endings()
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {line, line_index}, offset ->
      next_offset = offset + byte_size(line)

      if target_offset <= next_offset do
        line_bytes = binary_part(line, 0, target_offset - offset)
        {:halt, {:ok, %{line: line_index, character: utf16_units(line_bytes)}}}
      else
        {:cont, next_offset}
      end
    end)
  end

  defp split_lines_with_endings(""), do: [""]

  defp split_lines_with_endings(text) do
    Regex.split(~r/(?<=\n)/, text, trim: false)
  end

  defp utf16_character_to_line_offset(line, target_character) do
    line
    |> String.graphemes()
    |> Enum.reduce_while({0, 0}, fn grapheme, {bytes, units} ->
      cond do
        units == target_character ->
          {:halt, {:ok, bytes}}

        units > target_character ->
          {:halt, :error}

        true ->
          {:cont, {bytes + byte_size(grapheme), units + utf16_units(grapheme)}}
      end
    end)
    |> case do
      {:ok, _bytes} = result -> result
      {bytes, units} when units == target_character -> {:ok, bytes}
      _ -> :error
    end
  end

  defp utf16_units(binary) do
    binary
    |> String.to_charlist()
    |> Enum.reduce(0, fn codepoint, count ->
      if codepoint > 0xFFFF, do: count + 2, else: count + 1
    end)
  end
end
```

- [ ] **Step 4: Run the position tests**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add server/apps/phoenix_ls/lib/phoenix_ls/support/positions.ex server/apps/phoenix_ls/test/phoenix_ls/support/positions_test.exs
git commit -m "feat: add lsp position conversion utilities"
```

Expected: local commit succeeds. Do not push.

## Task 6: Add Semantic Regex Enforcement

**Files:**
- Create: `server/apps/phoenix_ls/test/phoenix_ls/architecture/regex_policy_test.exs`

- [ ] **Step 1: Write the failing policy test**

Create `server/apps/phoenix_ls/test/phoenix_ls/architecture/regex_policy_test.exs`:

```elixir
defmodule PhoenixLS.Architecture.RegexPolicyTest do
  use ExUnit.Case, async: true

  @restricted_dirs [
    "lib/phoenix_ls/parsing",
    "lib/phoenix_ls/introspection",
    "lib/phoenix_ls/features"
  ]

  @allowed_regex_files [
    "lib/phoenix_ls/support/positions.ex"
  ]

  test "semantic modules do not use regex parsing" do
    violations =
      @restricted_dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
      |> Enum.reject(&(&1 in @allowed_regex_files))
      |> Enum.filter(fn path ->
        source = File.read!(path)
        String.contains?(source, "Regex.") or String.contains?(source, "~r/")
      end)

    assert violations == []
  end
end
```

- [ ] **Step 2: Run the policy test**

Run:

```bash
cd server/apps/phoenix_ls && mix test test/phoenix_ls/architecture/regex_policy_test.exs
```

Expected: PASS while restricted directories do not exist or contain no regex.

- [ ] **Step 3: Commit**

Run:

```bash
git add server/apps/phoenix_ls/test/phoenix_ls/architecture/regex_policy_test.exs
git commit -m "test: enforce no semantic regex parsing"
```

Expected: local commit succeeds. Do not push.

## Task 7: Create v2 Scope Matrix

**Files:**
- Create: `docs/elixir-v2-scope-matrix.md`

- [ ] **Step 1: Create the v2-only scope matrix**

Create `docs/elixir-v2-scope-matrix.md`:

```markdown
# PhoenixLS Elixir v2 Scope Matrix

This is not a migration or parity checklist. The old TypeScript server is not a contract.

## Status Values

- `build-now`: required for the first usable v2 foundation or core feature set
- `later`: valuable after the core server is stable
- `out-of-scope`: intentionally not part of v2

## Foundation

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| Elixir umbrella under `server/` | build-now | Clean v2 server home | Mix compile and application smoke test |
| GenLSP lifecycle | build-now | initialize/shutdown/document sync foundation | JSON-RPC or GenLSP callback tests |
| Document store | build-now | Open editor buffers are source of truth | open/change/close tests |
| UTF-16 position conversion | build-now | Required for all LSP ranges | Unicode, CRLF, HEEx offset tests |
| Regex enforcement | build-now | Prevent semantic regex parsing | architecture policy test |

## Core Phoenix Intelligence

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| HEEx cursor context | build-now | Needed before completions | parser/cursor fixture tests |
| Function component extraction | build-now | Component completions and definitions | fixture component tests |
| Attribute and slot extraction | build-now | Component attribute/slot completions | fixture component tests |
| Router extraction | build-now | Verified route completions | Phoenix fixture tests |
| Schema extraction | build-now | Form/schema completions | Ecto fixture tests |
| LiveView event extraction | build-now | `phx-*` event completions | LiveView fixture tests |
| Diagnostics | build-now | Start with high-signal Phoenix mistakes | feature diagnostics tests |

## Editor Surfaces

| Area | Status | Notes | Required Tests |
| --- | --- | --- | --- |
| VS Code launcher | later | TypeScript client only, Elixir server core | extension activation smoke test |
| Neovim launcher | later | Lua client only, Elixir server core | local nvim config smoke test |
| Project explorer UI | later | Rebuild only if v2 custom requests justify it | custom request contract tests |
| ERD viewer | later | Not foundation work | explicit feature tests if rebuilt |

## Explicitly Out Of Scope For Foundation

| Area | Status | Reason |
| --- | --- | --- |
| TypeScript server migration | out-of-scope | Clean Elixir v2 rewrite |
| Old behavior parity | out-of-scope | v2 design owns behavior |
| Regex semantic parser | out-of-scope | Parser APIs and AST only |
| Go server core | out-of-scope | Phoenix semantics belong in Elixir |
```

- [ ] **Step 2: Confirm the matrix is tracked**

Run:

```bash
git check-ignore -v docs/elixir-v2-scope-matrix.md || true
```

Expected: no output. If it is ignored, add a narrow `.gitignore` exception for `!docs/elixir-v2-scope-matrix.md`.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/elixir-v2-scope-matrix.md
git commit -m "docs: define elixir v2 scope matrix"
```

Expected: local commit succeeds. Do not push.

## Task 8: Run Foundation Verification

**Files:**
- Verify only.

- [ ] **Step 1: Format Elixir files**

Run:

```bash
cd server && mix format
```

Expected: command succeeds.

- [ ] **Step 2: Run all foundation tests**

Run:

```bash
cd server && mix test
```

Expected: all tests pass.

- [ ] **Step 3: Compile with warnings as errors**

Run:

```bash
cd server && mix compile --warnings-as-errors
```

Expected: compile succeeds without warnings.

- [ ] **Step 4: Inspect final status**

Run:

```bash
git status --short
```

Expected: clean working tree after all task commits, or only intentional uncommitted changes if commits were skipped by user request.

## Self-Review

- Spec coverage: This plan implements the first foundation slice from the rewrite plan: clean Elixir project structure, GenLSP direction, document store, UTF-16 position conversion, regex enforcement, and v2-only scope matrix.
- Not covered yet: manager/engine split implementation, project compilation, Phoenix introspection, HEEx parsing, completions, hover, definition, diagnostics, packaging, VS Code launcher, and Neovim launcher. These require follow-up plans.
- Placeholder scan: No `TBD`, `TODO`, or unspecified implementation steps are intentionally present.
- Type consistency: Module names use the `PhoenixLS.*` namespace and file paths match the new `server/apps/phoenix_ls` umbrella layout.
