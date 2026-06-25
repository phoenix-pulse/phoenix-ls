defmodule PhoenixLS.Project.CompileEnvTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.CompileEnv
  alias PhoenixLS.Support.URI, as: SupportURI

  test "builds isolated Mix paths for a project root", context do
    root = tmp_dir(context, "project")
    cache_root = tmp_dir(context, "cache")
    root_uri = SupportURI.path_to_file_uri!(root)

    server =
      start_supervised!(
        {CompileEnv,
         root_uri: root_uri, cache_root: cache_root, source_only?: false, timeout_ms: 7_500}
      )

    assert %CompileEnv{
             root_uri: ^root_uri,
             root_path: ^root,
             cache_root: ^cache_root,
             build_path: build_path,
             deps_path: deps_path,
             mix_home: mix_home,
             archives_path: archives_path,
             timeout_ms: 7_500,
             source_only?: false
           } = CompileEnv.fetch(server)

    assert String.starts_with?(build_path, cache_root)
    assert String.starts_with?(deps_path, cache_root)
    assert String.starts_with?(mix_home, cache_root)
    assert String.starts_with?(archives_path, cache_root)
    refute build_path == Path.join(root, "_build")
    refute deps_path == Path.join(root, "deps")
    assert File.dir?(build_path)
    assert File.dir?(deps_path)
    assert File.dir?(mix_home)
    assert File.dir?(archives_path)
  end

  test "exports Mix environment variables for isolated project work", context do
    root = tmp_dir(context, "project")
    server = start_supervised!({CompileEnv, root_uri: SupportURI.path_to_file_uri!(root)})

    env = CompileEnv.fetch(server)

    assert CompileEnv.mix_env(env) == %{
             "MIX_BUILD_PATH" => env.build_path,
             "MIX_DEPS_PATH" => env.deps_path,
             "MIX_HOME" => env.mix_home,
             "MIX_ARCHIVES" => env.archives_path
           }
  end

  test "uses distinct cache paths for roots with the same basename", context do
    first_root = Path.join(tmp_dir(context, "first"), "app")
    second_root = Path.join(tmp_dir(context, "second"), "app")
    cache_root = tmp_dir(context, "cache")

    File.mkdir_p!(first_root)
    File.mkdir_p!(second_root)

    first =
      start_supervised!(
        {CompileEnv, root_uri: SupportURI.path_to_file_uri!(first_root), cache_root: cache_root},
        id: :first_compile_env
      )

    second =
      start_supervised!(
        {CompileEnv, root_uri: SupportURI.path_to_file_uri!(second_root), cache_root: cache_root},
        id: :second_compile_env
      )

    first_env = CompileEnv.fetch(first)
    second_env = CompileEnv.fetch(second)

    refute first_env.build_path == second_env.build_path
    refute first_env.deps_path == second_env.deps_path
    refute first_env.mix_home == second_env.mix_home
  end

  test "does not read or execute project code", context do
    root = tmp_dir(context, "project")
    File.write!(Path.join(root, "mix.exs"), ~s(raise "project code was executed"\n))

    server = start_supervised!({CompileEnv, root_uri: SupportURI.path_to_file_uri!(root)})

    assert %CompileEnv{root_path: ^root} = CompileEnv.fetch(server)
  end

  defp tmp_dir(context, name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_compile_env_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
