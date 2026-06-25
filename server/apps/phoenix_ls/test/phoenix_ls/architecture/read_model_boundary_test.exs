defmodule PhoenixLS.Architecture.ReadModelBoundaryTest do
  use ExUnit.Case, async: true

  @app_root Path.expand("../../..", __DIR__)

  @lsp_boundary_files [
    "lib/phoenix_ls/lsp/completion.ex",
    "lib/phoenix_ls/lsp/hover.ex",
    "lib/phoenix_ls/lsp/definition.ex",
    "lib/phoenix_ls/lsp/phoenix_requests.ex",
    "lib/phoenix_ls/lsp/diagnostics.ex"
  ]

  @store_read_tokens [
    "IndexStore.all(",
    "Store.all("
  ]

  @snapshot_flattening_files [
    "lib/phoenix_ls/lsp/phoenix_requests.ex"
  ]

  test "LSP request and diagnostics boundaries read index snapshots, not broad mutable stores" do
    violations =
      @lsp_boundary_files
      |> Enum.map(&Path.join(@app_root, &1))
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?(@store_read_tokens)
      end)
      |> Enum.map(&Path.relative_to(&1, @app_root))

    assert violations == []
  end

  test "Phoenix explorer requests pass snapshots without flattening them in the LSP layer" do
    violations =
      @snapshot_flattening_files
      |> Enum.map(&Path.join(@app_root, &1))
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("Snapshot.all(")
      end)
      |> Enum.map(&Path.relative_to(&1, @app_root))

    assert violations == []
  end
end
