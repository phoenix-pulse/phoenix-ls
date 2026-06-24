defmodule PhoenixLS.CLI do
  @moduledoc """
  Command-line entrypoint for the PhoenixLS executable.
  """

  alias PhoenixLS.LSP.Runtime

  @usage """
  Usage: phoenix_ls [--stdio]

  Options:
    --stdio      Start the language server over standard IO
    --version    Print the PhoenixLS version
    --help       Print this help text
  """

  @spec main([String.t()]) :: :ok
  def main(args) do
    case args do
      [] -> start_stdio()
      ["--stdio"] -> start_stdio()
      ["--version"] -> print_version()
      ["--help"] -> print_help()
      _unknown -> print_help()
    end
  end

  defp start_stdio do
    {:ok, _apps} = Application.ensure_all_started(:phoenix_ls)
    {:ok, _pid} = Runtime.start_link()

    Process.sleep(:infinity)
    :ok
  end

  defp print_version do
    IO.puts("PhoenixLS #{PhoenixLS.version()}")
    :ok
  end

  defp print_help do
    IO.write(@usage)
    :ok
  end
end
