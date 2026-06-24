defmodule PhoenixLS.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "mix project configures the PhoenixLS CLI as the escript entrypoint" do
    assert PhoenixLS.MixProject.project()[:escript][:main_module] == PhoenixLS.CLI
  end

  test "prints the server version" do
    output =
      capture_io(fn ->
        assert PhoenixLS.CLI.main(["--version"]) == :ok
      end)

    assert output == "PhoenixLS #{PhoenixLS.version()}\n"
  end

  test "prints usage for help" do
    output =
      capture_io(fn ->
        assert PhoenixLS.CLI.main(["--help"]) == :ok
      end)

    assert String.contains?(output, "Usage: phoenix_ls [--stdio]")
    assert String.contains?(output, "--version")
  end
end
