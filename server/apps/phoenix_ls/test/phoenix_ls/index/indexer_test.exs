defmodule PhoenixLS.Index.IndexerTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Index.{Indexer, Store}
  alias PhoenixLS.Project.{CompileEnv, CompileRunner, Engine, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.Document

  @store __MODULE__.Store
  @indexer __MODULE__.Indexer

  setup do
    start_supervised!({Store, name: @store})
    start_supervised!({Indexer, name: @indexer, index_store: @store})

    :ok
  end

  test "publishes structured status for startup project indexing", context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    project_store =
      Module.concat(__MODULE__, :"ProjectStatusStore#{System.unique_integer([:positive])}")

    project_indexer =
      Module.concat(__MODULE__, :"ProjectStatusIndexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: project_store}, id: {Store, project_store})

    start_supervised!(
      {Indexer,
       name: project_indexer,
       index_store: project_store,
       root_uri: root_uri,
       status_target: self()},
      id: {Indexer, project_indexer}
    )

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "started",
                      "job" => "project",
                      "rootUri" => ^root_uri
                    }},
                   500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "project",
                      "rootUri" => ^root_uri,
                      "result" => "ok",
                      "count" => 0
                    }},
                   500
  end

  test "publishes compilation status before startup project indexing", context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    compile_env = compile_env(root_uri, source_only?: false)
    parent = self()

    compile_runner =
      compile_runner(compile_env, fn command, args, opts ->
        send(parent, {:compile_command, command, args, opts})
        {"compiled", 0}
      end)

    project_store =
      Module.concat(__MODULE__, :"CompileStatusStore#{System.unique_integer([:positive])}")

    project_indexer =
      Module.concat(__MODULE__, :"CompileStatusIndexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: project_store}, id: {Store, project_store})

    start_supervised!(
      {Indexer,
       name: project_indexer,
       index_store: project_store,
       root_uri: root_uri,
       status_target: self(),
       compile_runner: compile_runner},
      id: {Indexer, project_indexer}
    )

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "compilation",
                      "phase" => "started",
                      "rootUri" => ^root_uri
                    }},
                   500

    assert_receive {:compile_command, "mix", ["compile", "--warnings-as-errors"], _opts}, 500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "compilation",
                      "phase" => "completed",
                      "rootUri" => ^root_uri,
                      "result" => "ok",
                      "sourceOnly" => false
                    }},
                   500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "started",
                      "job" => "project",
                      "rootUri" => ^root_uri
                    }},
                   500
  end

  test "publishes degraded status when compilation times out and continues project indexing",
       context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    compile_env = compile_env(root_uri, source_only?: false, timeout_ms: 10)

    compile_runner =
      compile_runner(compile_env, fn _command, _args, _opts ->
        Process.sleep(1_000)
        {"late", 0}
      end)

    project_store =
      Module.concat(__MODULE__, :"CompileTimeoutStore#{System.unique_integer([:positive])}")

    project_indexer =
      Module.concat(__MODULE__, :"CompileTimeoutIndexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: project_store}, id: {Store, project_store})

    start_supervised!(
      {Indexer,
       name: project_indexer,
       index_store: project_store,
       root_uri: root_uri,
       status_target: self(),
       compile_runner: compile_runner},
      id: {Indexer, project_indexer}
    )

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "compilation",
                      "phase" => "completed",
                      "rootUri" => ^root_uri,
                      "result" => "error: :timeout",
                      "sourceOnly" => false
                    }},
                   500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "project",
                      "state" => "degraded",
                      "rootUri" => ^root_uri,
                      "sourceOnly" => false,
                      "reason" => "{:compile, :timeout}"
                    }},
                   500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "project",
                      "rootUri" => ^root_uri,
                      "result" => "ok"
                    }},
                   500
  end

  test "asynchronously indexes an open Elixir document" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/page_live.ex",
        "elixir",
        3,
        """
        defmodule AppWeb.PageLive do
          def mount(params, session, socket), do: {:ok, socket}
        end
        """
      )

    assert Indexer.schedule_document(@indexer, document) == :ok

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.PageLive", "AppWeb.PageLive.mount/3"]
    end)
  end

  test "publishes structured status for document indexing" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/status_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.StatusLive do\nend\n"
      )

    assert Indexer.schedule_document(@indexer, document, status_target: self()) == :ok

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "started",
                      "job" => "document",
                      "uri" => "file:///tmp/app/lib/app_web/live/status_live.ex"
                    }},
                   500

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "document",
                      "uri" => "file:///tmp/app/lib/app_web/live/status_live.ex",
                      "result" => "ok",
                      "count" => 1
                    }},
                   500
  end

  test "asynchronously indexes an Elixir file from disk by URI", context do
    root = tmp_dir(context)
    path = Path.join([root, "lib", "disk_live.ex"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    defmodule AppWeb.DiskLive do
      def render(assigns), do: assigns
    end
    """)

    assert Indexer.schedule_uri(@indexer, SupportURI.path_to_file_uri!(path)) == :ok

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.DiskLive", "AppWeb.DiskLive.render/1"]
    end)
  end

  test "asynchronously indexes project source files from disk", context do
    root = tmp_dir(context)
    component_path = Path.join([root, "lib", "app_web", "components", "core_components.ex"])

    template_path =
      Path.join([root, "lib", "app_web", "controllers", "page_html", "index.html.heex"])

    File.mkdir_p!(Path.dirname(component_path))
    File.mkdir_p!(Path.dirname(template_path))

    File.write!(component_path, """
    defmodule AppWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button>Save</button>
        \"\"\"
      end
    end
    """)

    File.write!(template_path, "<section><.button /></section>\n")
    asset_path = Path.join([root, "priv", "static", "images", "logo.svg"])
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "<svg></svg>")

    assert Indexer.schedule_project(@indexer, SupportURI.path_to_file_uri!(root)) == :ok

    assert_eventually(fn ->
      assert ["AppWeb.CoreComponents.button/1"] =
               @store
               |> Store.by_kind(:component)
               |> Enum.map(& &1.id)

      assert [template] = Store.by_kind(@store, :template)
      assert template.uri == SupportURI.path_to_file_uri!(template_path)

      assert [asset] = Store.by_kind(@store, :asset)
      assert asset.id == "/images/logo.svg"
      assert asset.uri == SupportURI.path_to_file_uri!(asset_path)
      assert asset.provenance == %{source: :static_asset}
      assert asset.data.public_path == "/images/logo.svg"
      assert asset.data.type == :image
      assert asset.data.size == 11
    end)
  end

  test "asynchronously indexes umbrella app source files from disk", context do
    root = tmp_dir(context)

    component_path =
      Path.join([root, "apps", "shop", "lib", "shop_web", "components", "core_components.ex"])

    template_path =
      Path.join([
        root,
        "apps",
        "shop",
        "lib",
        "shop_web",
        "controllers",
        "page_html",
        "index.html.heex"
      ])

    File.mkdir_p!(Path.dirname(component_path))
    File.mkdir_p!(Path.dirname(template_path))

    File.write!(component_path, """
    defmodule ShopWeb.CoreComponents do
      def button(assigns) do
        ~H\"\"\"
        <button>Save</button>
        \"\"\"
      end
    end
    """)

    File.write!(template_path, "<section><.button /></section>\n")
    asset_path = Path.join([root, "apps", "shop", "priv", "static", "images", "logo.svg"])
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "<svg></svg>")

    assert Indexer.schedule_project(@indexer, SupportURI.path_to_file_uri!(root)) == :ok

    assert_eventually(fn ->
      assert ["ShopWeb.CoreComponents.button/1"] =
               @store
               |> Store.by_kind(:component)
               |> Enum.map(& &1.id)

      assert [template] = Store.by_kind(@store, :template)
      assert template.uri == SupportURI.path_to_file_uri!(template_path)

      assert [asset] = Store.by_kind(@store, :asset)
      assert asset.id == "/images/logo.svg"
      assert asset.uri == SupportURI.path_to_file_uri!(asset_path)
    end)
  end

  test "disabled project indexing skips disk warmup but keeps open document indexing", context do
    root = tmp_dir(context)
    path = Path.join([root, "lib", "disabled_project_live.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule AppWeb.DisabledProjectLive do\nend\n")
    root_uri = SupportURI.path_to_file_uri!(root)

    store =
      Module.concat(__MODULE__, :"DisabledProjectStore#{System.unique_integer([:positive])}")

    indexer =
      Module.concat(__MODULE__, :"DisabledProjectIndexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: store}, id: {Store, store})

    start_supervised!(
      {Indexer,
       name: indexer, index_store: store, status_target: self(), project_indexing_enabled: false},
      id: {Indexer, indexer}
    )

    assert Indexer.schedule_project(indexer, root_uri) == :ok

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "project",
                      "rootUri" => ^root_uri,
                      "result" => "disabled",
                      "count" => 0
                    }},
                   500

    assert Store.all(store) == []

    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/open_disabled_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.OpenDisabledLive do\nend\n"
      )

    assert Indexer.schedule_document(indexer, document) == :ok

    assert_eventually(fn ->
      assert index_ids(store) == ["AppWeb.OpenDisabledLive"]
    end)
  end

  test "invalidates facts for deleted uris" do
    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/delete_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.DeleteLive do\nend\n"
      )

    Indexer.schedule_document(@indexer, document)

    assert_eventually(fn ->
      assert index_ids(@store) == ["AppWeb.DeleteLive"]
    end)

    assert Indexer.delete_uri(@indexer, document.uri) == :ok

    assert_eventually(fn ->
      assert Store.by_uri(@store, document.uri) == []
    end)
  end

  test "notifies diagnostics target with changed dependency kinds after document indexing" do
    uri = "file:///tmp/app/lib/app_web/components/core_components.ex"

    first_document =
      Document.new(
        uri,
        "elixir",
        1,
        """
        defmodule AppWeb.CoreComponents do
          def button(assigns) do
            ~H\"\"\"
            <button>Save</button>
            \"\"\"
          end
        end
        """
      )

    second_document =
      Document.new(
        uri,
        "elixir",
        2,
        """
        defmodule AppWeb.CoreComponents do
          attr :label, :string, required: true

          def button(assigns) do
            ~H\"\"\"
            <button><%= @label %></button>
            \"\"\"
          end
        end
        """
      )

    assert Indexer.schedule_document(@indexer, first_document) == :ok

    assert_eventually(fn ->
      assert ["AppWeb.CoreComponents.button/1"] =
               @store
               |> Store.by_kind(:component)
               |> Enum.map(& &1.id)
    end)

    diagnostics = {self(), __MODULE__.DocumentStore, {:ok, :engine}}

    assert Indexer.schedule_document(@indexer, second_document, diagnostics: diagnostics) == :ok

    assert_receive {:phoenix_ls_index_changed, ^uri, changed_kinds, __MODULE__.DocumentStore,
                    {:ok, :engine}},
                   500

    assert MapSet.subset?(MapSet.new([:component, :component_attr]), changed_kinds)
  end

  test "emits telemetry for document, URI, project, and delete jobs", context do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach_many(
      handler_id,
      [
        [:phoenix_ls, :indexer, :document],
        [:phoenix_ls, :indexer, :uri],
        [:phoenix_ls, :indexer, :project],
        [:phoenix_ls, :indexer, :delete]
      ],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/telemetry_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.TelemetryLive do\nend\n"
      )

    root = tmp_dir(context)
    path = Path.join([root, "lib", "telemetry_disk_live.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule AppWeb.TelemetryDiskLive do\nend\n")
    uri = SupportURI.path_to_file_uri!(path)
    root_uri = SupportURI.path_to_file_uri!(root)

    Indexer.schedule_document(@indexer, document)
    Indexer.schedule_uri(@indexer, uri)
    Indexer.schedule_project(@indexer, root_uri)
    Indexer.delete_uri(@indexer, document.uri)

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :document], %{count: 1},
                    %{uri: "file:///tmp/app/lib/app_web/live/telemetry_live.ex"}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :uri], %{count: 1}, %{uri: ^uri}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :project], %{count: 1},
                    %{root_uri: ^root_uri, result: :ok}}

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :delete], %{count: 1},
                    %{uri: "file:///tmp/app/lib/app_web/live/telemetry_live.ex"}}
  end

  test "telemetry includes duration and performance budget metadata" do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach_many(
      handler_id,
      [[:phoenix_ls, :indexer, :document]],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    store = Module.concat(__MODULE__, :"BudgetStore#{System.unique_integer([:positive])}")
    indexer = Module.concat(__MODULE__, :"BudgetIndexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: store}, id: {Store, store})

    start_supervised!(
      {Indexer, name: indexer, index_store: store, performance_budgets_ms: %{document: 75}},
      id: {Indexer, indexer}
    )

    document =
      Document.new(
        "file:///tmp/app/lib/app_web/live/budget_live.ex",
        "elixir",
        1,
        "defmodule AppWeb.BudgetLive do\nend\n"
      )

    assert Indexer.schedule_document(indexer, document) == :ok

    assert_receive {:indexer_telemetry, [:phoenix_ls, :indexer, :document],
                    %{count: 1, duration_ms: duration_ms},
                    %{
                      uri: "file:///tmp/app/lib/app_web/live/budget_live.ex",
                      budget_ms: 75,
                      over_budget?: over_budget?
                    }},
                   500

    assert is_integer(duration_ms)
    assert duration_ms >= 0
    assert is_boolean(over_budget?)
  end

  test "project engines expose a named background indexer" do
    root_uri = "file:///tmp/phoenix-ls-indexer-engine"

    assert {:ok, pid} = Engine.start_link(root_uri: root_uri)
    assert is_pid(pid)
    assert is_pid(GenServer.whereis(Names.indexer(root_uri)))
  end

  defp index_ids(store) do
    store
    |> Store.all()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  def handle_telemetry(event, measurements, metadata, parent) do
    send(parent, {:indexer_telemetry, event, measurements, metadata})
  end

  defp assert_eventually(fun, attempts_left \\ 20)

  defp assert_eventually(fun, attempts_left) do
    fun.()
  rescue
    exception in [ExUnit.AssertionError, MatchError] ->
      if attempts_left > 0 do
        Process.sleep(10)
        assert_eventually(fun, attempts_left - 1)
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp tmp_dir(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_indexer_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    path
  end

  defp compile_env(root_uri, opts) do
    name = Module.concat(__MODULE__, :"CompileEnv#{System.unique_integer([:positive])}")

    start_supervised!(
      {CompileEnv, Keyword.merge([name: name, root_uri: root_uri], opts)},
      id: {CompileEnv, name}
    )
  end

  defp compile_runner(compile_env, command_runner) do
    name = Module.concat(__MODULE__, :"CompileRunner#{System.unique_integer([:positive])}")

    start_supervised!(
      {CompileRunner, name: name, compile_env: compile_env, command_runner: command_runner},
      id: {CompileRunner, name}
    )
  end
end
