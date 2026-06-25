defmodule PhoenixLS.Project.ManagerTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Project.{CompileEnv, Engine, Manager}
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Workspace.DocumentStore

  @document_uri "file:///tmp/page.html.heex"

  setup_all do
    ensure_project_registry_started()
  end

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
    %{manager: manager} =
      start_manager(__MODULE__.IsolationSupervisor, __MODULE__.IsolationManager)

    assert {:ok, first} =
             Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-one")

    assert {:ok, second} =
             Manager.ensure_engine(manager, "file:///tmp/phoenix-ls-manager-two")

    refute first.pid == second.pid
    refute first.document_store == second.document_store

    assert :ok = DocumentStore.open(first.document_store, @document_uri, "phoenix-heex", 1, "one")

    assert :ok =
             DocumentStore.open(second.document_store, @document_uri, "phoenix-heex", 1, "two")

    assert {:ok, first_doc} = DocumentStore.fetch(first.document_store, @document_uri)
    assert {:ok, second_doc} = DocumentStore.fetch(second.document_store, @document_uri)
    assert first_doc.text == "one"
    assert second_doc.text == "two"
  end

  test "forwards compile environment options to started engines", context do
    %{manager: manager} =
      start_manager(__MODULE__.CompileEnvSupervisor, __MODULE__.CompileEnvManager)

    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    cache_root = tmp_dir(context)

    assert {:ok, engine} =
             Manager.ensure_engine(manager, root_uri,
               source_only?: false,
               compile_timeout_ms: 12_000,
               compile_cache_root: cache_root
             )

    assert %CompileEnv{
             root_uri: ^root_uri,
             cache_root: ^cache_root,
             source_only?: false,
             timeout_ms: 12_000
           } = CompileEnv.fetch(engine.compile_env)
  end

  test "forwards project compilation options to started engines", context do
    %{manager: manager} =
      start_manager(__MODULE__.CompilationSupervisor, __MODULE__.CompilationManager)

    parent = self()
    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule CompilationFixture.MixProject do
      use Mix.Project

      def project do
        [app: :compilation_fixture, version: "0.1.0", deps: []]
      end
    end
    """)

    assert {:ok, %Engine{}} =
             Manager.ensure_engine(manager, root_uri,
               source_only?: false,
               project_compilation_enabled: true,
               status_target: self(),
               compile_command_runner: fn command, args, opts ->
                 send(parent, {:compile_command, command, args, opts})
                 {"compiled", 0}
               end
             )

    assert_receive {:compile_command, "mix", ["compile", "--warnings-as-errors"], _opts}, 500
  end

  test "fetch_engine and document_store report missing roots without starting engines" do
    %{manager: manager} = start_manager(__MODULE__.MissingSupervisor, __MODULE__.MissingManager)

    assert Manager.fetch_engine(manager, "file:///tmp/missing") == :error
    assert Manager.document_store(manager, "file:///tmp/missing") == :error
  end

  test "ensure_project_for_uri canonicalizes nested file URI to the Mix root URI", context do
    %{manager: manager} =
      start_manager(__MODULE__.LocatedSupervisor, __MODULE__.LocatedManager)

    root = fixture_project(context, "located")
    file_path = Path.join([root, "lib", "located.ex"])
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "defmodule Located do\nend\n")

    root_uri = SupportURI.path_to_file_uri!(root)
    file_uri = SupportURI.path_to_file_uri!(file_path)

    assert {:ok, first} = Manager.ensure_project_for_uri(manager, file_uri)
    assert {:ok, second} = Manager.ensure_project_for_uri(manager, root_uri)

    assert first.root_uri == root_uri
    assert first.pid == second.pid
    assert first.document_store == second.document_store
  end

  test "ensure_project_for_uri does not execute project mix or source code", context do
    %{manager: manager} =
      start_manager(__MODULE__.NoProjectCodeSupervisor, __MODULE__.NoProjectCodeManager)

    root = tmp_dir(context)
    root_uri = SupportURI.path_to_file_uri!(root)
    sentinel_path = Path.join(root, "project_code_executed")

    File.write!(Path.join(root, "mix.exs"), """
    File.write!(#{inspect(sentinel_path)}, "mix executed")

    defmodule NoProjectCode.MixProject do
      use Mix.Project

      def project do
        [app: :no_project_code, version: "0.1.0", deps: [{:phoenix, "~> 1.8"}]]
      end
    end
    """)

    file_path = Path.join([root, "lib", "no_project_code_web", "live", "page_live.ex"])
    File.mkdir_p!(Path.dirname(file_path))

    File.write!(file_path, """
    File.write!(#{inspect(sentinel_path)}, "source executed")

    defmodule NoProjectCodeWeb.PageLive do
      use Phoenix.LiveView

      def render(assigns), do: ~H"<div>{@title}</div>"
    end
    """)

    assert {:ok, engine} =
             Manager.ensure_project_for_uri(manager, SupportURI.path_to_file_uri!(file_path),
               status_target: self()
             )

    assert engine.root_uri == root_uri

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "project",
                      "rootUri" => ^root_uri
                    }},
                   500

    refute File.exists?(sentinel_path)
  end

  test "ensure_project_for_uri returns error for files outside Mix projects", context do
    %{manager: manager} =
      start_manager(__MODULE__.NoProjectSupervisor, __MODULE__.NoProjectManager)

    dir = tmp_dir(context)
    file_path = Path.join([dir, "lib", "orphan.ex"])
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "defmodule Orphan do\nend\n")

    assert Manager.ensure_project_for_uri(manager, SupportURI.path_to_file_uri!(file_path)) ==
             :error
  end

  defp start_manager(supervisor_name, manager_name) do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: supervisor_name})
    manager = start_supervised!({Manager, name: manager_name, engine_supervisor: supervisor_name})

    %{manager: manager}
  end

  defp fixture_project(context, name) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule Located.MixProject do
      use Mix.Project

      def project do
        [app: :located, version: "0.1.0", deps: []]
      end
    end
    """)

    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)

    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_manager_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
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
end
