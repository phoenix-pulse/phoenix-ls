defmodule PhoenixLS.Project.CompileRunnerTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.{CompileEnv, CompileRunner}
  alias PhoenixLS.Support.URI, as: SupportURI

  test "returns source-only fallback without invoking Mix", context do
    parent = self()
    root = tmp_dir(context, "project")

    compile_env =
      start_supervised!(
        {CompileEnv, root_uri: SupportURI.path_to_file_uri!(root), source_only?: true}
      )

    runner =
      start_supervised!(
        {CompileRunner,
         compile_env: compile_env,
         command_runner: fn command, args, opts ->
           send(parent, {:unexpected_command, command, args, opts})
           {"unexpected", 0}
         end}
      )

    assert CompileRunner.run(runner, ["compile"]) == {:error, :source_only}
    refute_receive {:unexpected_command, _command, _args, _opts}
  end

  test "runs Mix with isolated project environment", context do
    parent = self()
    root = tmp_dir(context, "project")
    cache_root = tmp_dir(context, "cache")

    compile_env =
      start_supervised!(
        {CompileEnv,
         root_uri: SupportURI.path_to_file_uri!(root), cache_root: cache_root, source_only?: false}
      )

    runner =
      start_supervised!(
        {CompileRunner,
         compile_env: compile_env,
         command_runner: fn command, args, opts ->
           send(parent, {:command, command, args, opts})
           {"compiled", 0}
         end}
      )

    assert {:ok, %CompileRunner.Result{output: "compiled", status: 0}} =
             CompileRunner.run(runner, ["compile", "--warnings-as-errors"])

    env = CompileEnv.fetch(compile_env)

    assert_receive {:command, "mix", ["compile", "--warnings-as-errors"], opts}
    assert opts[:cd] == root
    assert opts[:stderr_to_stdout] == true
    assert Enum.sort(opts[:env]) == Enum.sort(Map.to_list(CompileEnv.mix_env(env)))
  end

  test "returns timeout when Mix work exceeds the compile environment timeout", context do
    root = tmp_dir(context, "project")

    compile_env =
      start_supervised!(
        {CompileEnv,
         root_uri: SupportURI.path_to_file_uri!(root), source_only?: false, timeout_ms: 10}
      )

    runner =
      start_supervised!(
        {CompileRunner,
         compile_env: compile_env,
         command_runner: fn _command, _args, _opts ->
           Process.sleep(1_000)
           {"late", 0}
         end}
      )

    assert CompileRunner.run(runner, ["compile"]) == {:error, :timeout}
  end

  defp tmp_dir(context, name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_compile_runner_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
