defmodule PhoenixLS.Project.EngineTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{Fact, Store}
  alias PhoenixLS.Project.{CompileEnv, Engine, Metadata, Names}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  @root_uri "file:///tmp/phoenix-ls-engine-test"
  @document_uri "file:///tmp/page.html.heex"

  setup_all do
    ensure_project_registry_started()
  end

  test "starts a named engine and project document store for the root uri" do
    assert {:ok, pid} = Engine.start_link(root_uri: @root_uri)
    assert is_pid(pid)

    document_store = Names.document_store(@root_uri)

    assert :ok =
             DocumentStore.open(
               document_store,
               @document_uri,
               "phoenix-heex",
               1,
               "hello"
             )

    assert {:ok, document} = DocumentStore.fetch(document_store, @document_uri)
    assert document.text == "hello"

    index_store = Names.index_store(@root_uri)
    fact = fact(:module, "AppWeb.PageLive", @document_uri)

    assert :ok = Store.put(index_store, fact)
    assert Store.all(index_store) == [fact]
  end

  test "warm-indexes project source files on startup", context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
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

    assert {:ok, _pid} = Engine.start_link(root_uri: root_uri)

    assert_eventually(fn ->
      assert ["AppWeb.CoreComponents.button/1"] =
               root_uri
               |> Names.index_store()
               |> Store.by_kind(:component)
               |> Enum.map(& &1.id)

      assert [template] =
               root_uri
               |> Names.index_store()
               |> Store.by_kind(:template)

      assert template.uri == SupportURI.path_to_file_uri!(template_path)
    end)
  end

  test "starts engine-owned project metadata", context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule App.MixProject do
      use Mix.Project

      def project do
        [app: :app, version: "0.1.0", deps: [{:phoenix_live_view, "~> 1.0"}]]
      end
    end
    """)

    assert {:ok, _pid} = Engine.start_link(root_uri: root_uri)

    assert %Metadata{
             root_uri: ^root_uri,
             root_path: ^root,
             phoenix?: true
           } = Metadata.fetch(Names.metadata(root_uri))
  end

  test "starts engine-owned compile environment", context do
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    assert {:ok, _pid} =
             Engine.start_link(root_uri: root_uri, source_only?: false, compile_timeout_ms: 9_000)

    assert %CompileEnv{
             root_uri: ^root_uri,
             root_path: ^root,
             source_only?: false,
             timeout_ms: 9_000
           } = CompileEnv.fetch(Names.compile_env(root_uri))
  end

  test "builds a handle with the engine pid and project-owned process names" do
    pid = self()

    assert %Engine{
             root_uri: @root_uri,
             pid: ^pid,
             document_store: document_store,
             compile_env: compile_env,
             index_store: index_store,
             metadata: metadata
           } = Engine.handle(@root_uri, pid)

    assert document_store == Names.document_store(@root_uri)
    assert compile_env == Names.compile_env(@root_uri)
    assert index_store == Names.index_store(@root_uri)
    assert metadata == Names.metadata(@root_uri)
  end

  defp ensure_project_registry_started do
    case Process.whereis(PhoenixLS.Project.Registry) do
      nil ->
        {:ok, pid} = Registry.start_link(keys: :unique, name: PhoenixLS.Project.Registry)

        on_exit(fn ->
          if Process.alive?(pid), do: Process.exit(pid, :normal)
        end)

      _pid ->
        :ok
    end
  end

  defp fact(kind, id, uri) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: uri,
      range: %Range{
        start: %Position{line: 0, character: 0},
        end: %Position{line: 0, character: 1}
      },
      provenance: %{source: :engine_test}
    )
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
        "phoenix_ls_engine_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
