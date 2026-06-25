defmodule PhoenixLS.Project.CompileRunner do
  @moduledoc """
  Engine-owned runner for isolated Mix commands.
  """

  use GenServer

  alias PhoenixLS.Project.CompileEnv

  defmodule Result do
    @moduledoc """
    Result from an isolated Mix command.
    """

    @enforce_keys [:output, :status]
    defstruct [:output, :status]

    @type t :: %__MODULE__{
            output: String.t(),
            status: non_neg_integer()
          }
  end

  @enforce_keys [:compile_env, :command_runner]
  defstruct [:compile_env, :command_runner]

  @type command_runner :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})
  @type t :: %__MODULE__{
          compile_env: GenServer.server(),
          command_runner: command_runner()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec run(GenServer.server(), [String.t()]) ::
          {:ok, Result.t()} | {:error, :source_only | :timeout | :unavailable | term()}
  def run(server, args) when is_list(args) do
    GenServer.call(server, {:run, args}, :infinity)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      compile_env: Keyword.fetch!(opts, :compile_env),
      command_runner: Keyword.get(opts, :command_runner, &System.cmd/3)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:run, args}, _from, state) do
    env = CompileEnv.fetch(state.compile_env)

    reply =
      cond do
        env.source_only? -> {:error, :source_only}
        is_nil(env.root_path) -> {:error, :unavailable}
        true -> run_with_timeout(state.command_runner, args, env)
      end

    {:reply, reply, state}
  end

  defp run_with_timeout(command_runner, args, env) do
    task =
      Task.async(fn ->
        command_runner.("mix", args, command_opts(env))
      end)

    case Task.yield(task, env.timeout_ms) do
      {:ok, result} ->
        normalize_result(result)

      {:exit, reason} ->
        {:error, {:exit, reason}}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp command_opts(env) do
    [
      cd: env.root_path,
      env: Map.to_list(CompileEnv.mix_env(env)),
      stderr_to_stdout: true
    ]
  end

  defp normalize_result({output, status}) when is_binary(output) and is_integer(status) do
    {:ok, %Result{output: output, status: status}}
  end

  defp normalize_result(result), do: {:error, {:invalid_result, result}}
end
