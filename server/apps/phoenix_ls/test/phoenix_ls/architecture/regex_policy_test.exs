defmodule PhoenixLS.Architecture.RegexPolicyTest do
  use ExUnit.Case, async: true

  @app_root Path.expand("../../..", __DIR__)

  @restricted_dirs [
    "lib/phoenix_ls/parsing",
    "lib/phoenix_ls/introspection",
    "lib/phoenix_ls/features"
  ]

  @disallowed_regex_tokens [
    "Regex.",
    "~r/",
    "~r\"",
    "~r'",
    "~r|",
    "~r(",
    "~r[",
    "~r{",
    "~r<"
  ]

  test "semantic modules do not use regex parsing" do
    violations =
      @restricted_dirs
      |> Enum.flat_map(fn dir ->
        Path.wildcard(Path.join([@app_root, dir, "**/*.ex"]))
      end)
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?(@disallowed_regex_tokens)
      end)

    assert violations == []
  end
end
