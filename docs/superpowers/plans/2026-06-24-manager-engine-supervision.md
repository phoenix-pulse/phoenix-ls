# Manager Engine Supervision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first OTP manager/engine boundary so each initialized project root can own isolated runtime state.

**Architecture:** `PhoenixLS.Project.Manager` is the manager-side registry API; it starts and finds project engines but does not load or execute project code. `PhoenixLS.Project.Engine` is a per-root supervisor that owns project-local children, starting with an isolated `DocumentStore`. `PhoenixLS.LSP.Server` keeps protocol handling thin and, on initialize, asks the manager for the engine matching `root_uri` and assigns that engine's document store for later text sync.

**Tech Stack:** Elixir, OTP `Registry`, `DynamicSupervisor`, `Supervisor`, GenServer, GenLSP, ExUnit.

---

## File Structure

- Create `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
  - Centralizes `Registry` names for project engines and project document stores.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
  - Defines the project engine handle struct.
  - Starts a per-root supervisor named through the project registry.
  - Supervises a per-root `PhoenixLS.Workspace.DocumentStore`.
- Create `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
  - Provides `ensure_engine/2`, `fetch_engine/2`, and `document_store/2`.
  - Uses `DynamicSupervisor` to start project engines.
  - Uses `Registry.lookup/2` as the source of truth for existing engines.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`
  - Start `PhoenixLS.Project.Registry`.
  - Start `PhoenixLS.Project.EngineSupervisor`.
  - Start `PhoenixLS.Project.Manager`.
  - Keep the current global `DocumentStore` fallback for sessions without a root URI and existing tests.
- Modify `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
  - Assign default `:project_manager`.
  - On initialize with a non-nil `root_uri`, ensure a project engine and assign that engine's document store.
  - On initialize with nil `root_uri`, keep the fallback document store.
- Create `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`
  - Verify a project engine starts a per-root document store and does not share document state.
- Create `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`
  - Verify manager idempotently starts one engine per root.
  - Verify different roots get different engine/document store owners.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`
  - Verify the application starts project registry, engine supervisor, manager, and fallback document store.
- Modify `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
  - Verify `Server.init/2` stores the default project manager.
  - Verify initialize assigns a per-project document store for non-nil roots.
- Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`
  - Verify initialize followed by text document sync writes into the root's engine document store over GenLSP transport.

## Task 1: Project Engine Supervisor

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex`
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`

- [ ] **Step 1: Write failing engine tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs`:

```elixir
defmodule PhoenixLS.Project.EngineTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.{Engine, Names}
  alias PhoenixLS.Workspace.DocumentStore

  @root_uri "file:///tmp/phoenix-ls-engine-test"

  test "starts a named engine and project document store for the root uri" do
    start_supervised!({Registry, keys: :unique, name: PhoenixLS.Project.Registry})

    assert {:ok, pid} = Engine.start_link(root_uri: @root_uri)
    assert is_pid(pid)

    document_store = Names.document_store(@root_uri)
    assert :ok = DocumentStore.open(document_store, "file:///tmp/page.html.heex", "phoenix-heex", 1, "hello")
    assert {:ok, document} = DocumentStore.fetch(document_store, "file:///tmp/page.html.heex")
    assert document.text == "hello"
  end

  test "builds a handle with the engine pid and document store" do
    pid = self()

    assert %Engine{
             root_uri: @root_uri,
             pid: ^pid,
             document_store: document_store
           } = Engine.handle(@root_uri, pid)

    assert document_store == Names.document_store(@root_uri)
  end
end
```

- [ ] **Step 2: Run engine tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs
```

Expected: FAIL because `PhoenixLS.Project.Engine` and `PhoenixLS.Project.Names` do not exist.

- [ ] **Step 3: Implement names and engine**

Create `PhoenixLS.Project.Names`:

```elixir
defmodule PhoenixLS.Project.Names do
  @moduledoc """
  Process names for project-scoped runtime state.
  """

  @registry PhoenixLS.Project.Registry

  @spec engine(String.t()) :: GenServer.server()
  def engine(root_uri), do: via({:engine, root_uri})

  @spec document_store(String.t()) :: GenServer.server()
  def document_store(root_uri), do: via({:document_store, root_uri})

  defp via(key), do: {:via, Registry, {@registry, key}}
end
```

Create `PhoenixLS.Project.Engine`:

```elixir
defmodule PhoenixLS.Project.Engine do
  @moduledoc """
  Per-project supervision island for runtime state.
  """

  use Supervisor

  alias PhoenixLS.Project.Names
  alias PhoenixLS.Workspace.DocumentStore

  @enforce_keys [:root_uri, :pid, :document_store]
  defstruct [:root_uri, :pid, :document_store]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          pid: pid(),
          document_store: GenServer.server()
        }

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    name = Keyword.get(opts, :name, Names.engine(root_uri))

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec handle(String.t(), pid()) :: t()
  def handle(root_uri, pid) do
    %__MODULE__{
      root_uri: root_uri,
      pid: pid,
      document_store: Names.document_store(root_uri)
    }
  end

  @impl true
  def init(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)
    document_store = Keyword.get(opts, :document_store, Names.document_store(root_uri))

    children = [
      {DocumentStore, name: document_store}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

- [ ] **Step 4: Run engine tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs
```

Expected: PASS.

## Task 2: Project Manager

**Files:**
- Create: `server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`

- [ ] **Step 1: Write failing manager tests**

Create `server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs`:

```elixir
defmodule PhoenixLS.Project.ManagerTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.{Engine, Manager}
  alias PhoenixLS.Workspace.DocumentStore

  test "ensure_engine starts and reuses one engine per root uri" do
    %{manager: manager} = start_manager(__MODULE__.ReuseSupervisor, __MODULE__.ReuseManager)
    root_uri = "file:///tmp/phoenix-ls-manager-reuse"

    assert {:ok, %Engine{} = first} = Manager.ensure_engine(manager, root_uri)
    assert {:ok, %Engine{} = second} = Manager.ensure_engine(manager, root_uri)

    assert first.root_uri == root_uri
    assert first.pid == second.pid
    assert first.document_store == second.document_store
  end

  test "different root uris receive isolated document stores" do
    %{manager: manager} = start_manager(__MODULE__.IsolationSupervisor, __MODULE__.IsolationManager)

    assert {:ok, first} = Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-one")
    assert {:ok, second} = Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-two")

    refute first.pid == second.pid
    refute first.document_store == second.document_store

    assert :ok = DocumentStore.open(first.document_store, "file:///tmp/page.html.heex", "phoenix-heex", 1, "one")
    assert :ok = DocumentStore.open(second.document_store, "file:///tmp/page.html.heex", "phoenix-heex", 1, "two")

    assert {:ok, first_doc} = DocumentStore.fetch(first.document_store, "file:///tmp/page.html.heex")
    assert {:ok, second_doc} = DocumentStore.fetch(second.document_store, "file:///tmp/page.html.heex")
    assert first_doc.text == "one"
    assert second_doc.text == "two"
  end

  test "fetch_engine and document_store report missing roots without starting engines" do
    %{manager: manager} = start_manager(__MODULE__.MissingSupervisor, __MODULE__.MissingManager)

    assert Manager.fetch_engine(manager, "file:///tmp/missing") == :error
    assert Manager.document_store(manager, "file:///tmp/missing") == :error
  end

  defp start_manager(supervisor_name, manager_name) do
    start_supervised!({Registry, keys: :unique, name: PhoenixLS.Project.Registry})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    %{manager: manager}
  end
end
```

- [ ] **Step 2: Run manager tests and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs
```

Expected: FAIL because `PhoenixLS.Project.Manager` does not exist.

- [ ] **Step 3: Implement manager API**

Create `PhoenixLS.Project.Manager` with:

```elixir
defmodule PhoenixLS.Project.Manager do
  @moduledoc """
  Manager-side API for project engine ownership.
  """

  use GenServer

  alias PhoenixLS.Project.{Engine, Names}

  @default_name __MODULE__
  @default_engine_supervisor PhoenixLS.Project.EngineSupervisor
  @registry PhoenixLS.Project.Registry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec ensure_engine(GenServer.server(), String.t()) :: {:ok, Engine.t()} | {:error, term()}
  def ensure_engine(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:ensure_engine, root_uri})
  end

  @spec fetch_engine(GenServer.server(), String.t()) :: {:ok, Engine.t()} | :error
  def fetch_engine(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:fetch_engine, root_uri})
  end

  @spec document_store(GenServer.server(), String.t()) :: {:ok, GenServer.server()} | :error
  def document_store(server \\ @default_name, root_uri) when is_binary(root_uri) do
    GenServer.call(server, {:document_store, root_uri})
  end

  @impl true
  def init(opts) do
    state = %{engine_supervisor: Keyword.get(opts, :engine_supervisor, @default_engine_supervisor)}

    {:ok, state}
  end

  @impl true
  def handle_call({:ensure_engine, root_uri}, _from, state) do
    {:reply, ensure_engine_started(state.engine_supervisor, root_uri), state}
  end

  def handle_call({:fetch_engine, root_uri}, _from, state) do
    {:reply, fetch_engine_handle(root_uri), state}
  end

  def handle_call({:document_store, root_uri}, _from, state) do
    reply =
      case fetch_engine_handle(root_uri) do
        {:ok, engine} -> {:ok, engine.document_store}
        :error -> :error
      end

    {:reply, reply, state}
  end

  defp ensure_engine_started(engine_supervisor, root_uri) do
    case fetch_engine_handle(root_uri) do
      {:ok, engine} ->
        {:ok, engine}

      :error ->
        case DynamicSupervisor.start_child(engine_supervisor, {Engine, root_uri: root_uri}) do
          {:ok, pid} -> {:ok, Engine.handle(root_uri, pid)}
          {:error, {:already_started, pid}} -> {:ok, Engine.handle(root_uri, pid)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp fetch_engine_handle(root_uri) do
    case Registry.lookup(@registry, {:engine, root_uri}) do
      [{pid, _value}] -> {:ok, Engine.handle(root_uri, pid)}
      [] -> :error
    end
  end
end
```

- [ ] **Step 4: Run manager tests and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs
```

Expected: PASS.

## Task 3: Application Supervision

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/application.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`

- [ ] **Step 1: Write failing application supervision test**

Add to `server/apps/phoenix_ls/test/phoenix_ls/application_test.exs`:

```elixir
test "application starts manager, project engine supervisor, registry, and fallback document store" do
  assert Process.whereis(PhoenixLS.Project.Manager)
  assert Process.whereis(PhoenixLS.Project.EngineSupervisor)
  assert Process.whereis(PhoenixLS.Project.Registry)
  assert Process.whereis(PhoenixLS.Workspace.DocumentStore)
end
```

- [ ] **Step 2: Run application test and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/application_test.exs
```

Expected: FAIL because project manager, registry, and engine supervisor are not application children yet.

- [ ] **Step 3: Add project children to application supervisor**

Update `children` in `PhoenixLS.Application.start/2`:

```elixir
children = [
  {Registry, keys: :unique, name: PhoenixLS.Project.Registry},
  {DynamicSupervisor, strategy: :one_for_one, name: PhoenixLS.Project.EngineSupervisor},
  PhoenixLS.Project.Manager,
  PhoenixLS.Workspace.DocumentStore
]
```

- [ ] **Step 4: Run application test and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/application_test.exs
```

Expected: PASS.

## Task 4: LSP Initialize Project Routing

**Files:**
- Modify: `server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex`
- Modify: `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`
- Create: `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs`

- [ ] **Step 1: Write failing LSP callback test**

Update `server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs`:

```elixir
alias PhoenixLS.Project.{Manager, Names}
```

In the init test, add:

```elixir
assert LSP.assigns(initialized_lsp).project_manager == Manager
```

Add a callback test:

```elixir
test "initialize assigns the project engine document store for root uri sessions", %{lsp: lsp} do
  start_supervised!({Registry, keys: :unique, name: PhoenixLS.Project.Registry})
  start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.EngineSupervisor})
  manager =
    start_supervised!(
      {Manager, name: __MODULE__.Manager, engine_supervisor: __MODULE__.EngineSupervisor}
    )

  {:ok, lsp} = Server.init(lsp, project_manager: manager)
  root_uri = "file:///tmp/phoenix-ls-server-project-routing"

  params = %InitializeParams{
    process_id: nil,
    root_uri: root_uri,
    capabilities: %ClientCapabilities{}
  }

  assert {:reply, %InitializeResult{}, updated_lsp} =
           Server.handle_request(%Initialize{id: 1, params: params}, lsp)

  assert LSP.assigns(updated_lsp).root_uri == root_uri
  assert LSP.assigns(updated_lsp).document_store == Names.document_store(root_uri)
end
```

- [ ] **Step 2: Run LSP lifecycle test and verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: FAIL because `Server.init/2` does not assign `:project_manager` and initialize does not switch document stores.

- [ ] **Step 3: Implement initialize routing**

Update `Server.init/2`:

```elixir
project_manager = Keyword.get(args, :project_manager, PhoenixLS.Project.Manager)

assign(lsp,
  document_store: document_store,
  exit_code: 1,
  exit_handler: exit_handler,
  project_manager: project_manager,
  root_uri: nil
)
```

Update initialize handling:

```elixir
def handle_request(%Initialize{params: %InitializeParams{root_uri: root_uri}}, lsp) do
  lsp = assign_project(lsp, root_uri)

  result = %InitializeResult{
    capabilities: Capabilities.build(),
    server_info: %{name: "PhoenixLS", version: PhoenixLS.version()}
  }

  {:reply, result, assign(lsp, root_uri: root_uri)}
end

defp assign_project(lsp, nil), do: lsp

defp assign_project(lsp, root_uri) when is_binary(root_uri) do
  project_manager = GenLSP.LSP.assigns(lsp).project_manager

  case PhoenixLS.Project.Manager.ensure_engine(project_manager, root_uri) do
    {:ok, engine} -> assign(lsp, document_store: engine.document_store)
    {:error, _reason} -> lsp
  end
end
```

- [ ] **Step 4: Run LSP lifecycle test and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs
```

Expected: PASS.

- [ ] **Step 5: Write transport routing test**

Create `server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs` with a test that initializes with a `rootUri`, sends `didOpen`, and asserts the document appears in `Names.document_store(root_uri)`.

- [ ] **Step 6: Run transport routing test and verify GREEN**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
```

Expected: PASS.

## Task 5: Full Verification And Commit

**Files:**
- All changed files in this plan.

- [ ] **Step 1: Run formatting check**

Run:

```bash
cd server && mix format --check-formatted
```

Expected: PASS. If it fails, run `cd server && mix format`, inspect the diff, then rerun the check.

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

- [ ] **Step 4: Check no semantic regex was introduced**

Run:

```bash
rg -n "~r|Regex\\.|Regex|:re\\.|=~" server/apps/phoenix_ls/lib/phoenix_ls/project server/apps/phoenix_ls/lib/phoenix_ls/lsp server/apps/phoenix_ls/test/phoenix_ls/project server/apps/phoenix_ls/test/phoenix_ls/lsp || true
```

Expected: no output.

- [ ] **Step 5: Inspect git diff**

Run:

```bash
git diff --stat
git diff -- server/apps/phoenix_ls/lib/phoenix_ls/project server/apps/phoenix_ls/lib/phoenix_ls/application.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/test/phoenix_ls/project server/apps/phoenix_ls/test/phoenix_ls/application_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp
```

Expected: only the manager/engine plan, project supervision modules, app supervision, LSP initialize routing, and related tests changed.

- [ ] **Step 6: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-24-manager-engine-supervision.md server/apps/phoenix_ls/lib/phoenix_ls/project/names.ex server/apps/phoenix_ls/lib/phoenix_ls/project/engine.ex server/apps/phoenix_ls/lib/phoenix_ls/project/manager.ex server/apps/phoenix_ls/lib/phoenix_ls/application.ex server/apps/phoenix_ls/lib/phoenix_ls/lsp/server.ex server/apps/phoenix_ls/test/phoenix_ls/project/engine_test.exs server/apps/phoenix_ls/test/phoenix_ls/project/manager_test.exs server/apps/phoenix_ls/test/phoenix_ls/application_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/server_lifecycle_test.exs server/apps/phoenix_ls/test/phoenix_ls/lsp/project_document_sync_transport_test.exs
git commit -m "feat: add project manager engine supervision"
```

Expected: commit succeeds locally. Do not push.

## Self-Review

- Spec coverage: This plan adds the manager/engine split skeleton, project-local document stores, application supervision, and LSP initialize routing. It intentionally does not load Mix projects, compile user code, index files, parse Phoenix semantics, publish diagnostics, or remove the fallback global document store.
- Placeholder scan: No task uses placeholders or asks for unspecified tests.
- Type consistency: The plan consistently uses `PhoenixLS.Project.Engine` handles, `PhoenixLS.Project.Manager.ensure_engine/2`, `PhoenixLS.Project.Manager.fetch_engine/2`, `PhoenixLS.Project.Manager.document_store/2`, and `PhoenixLS.Project.Names.document_store/1`.
