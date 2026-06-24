defmodule PhoenixLS.LSP.Runtime do
  @moduledoc """
  Runtime supervisor for the editor-facing GenLSP process tree.
  """

  @default_name __MODULE__
  @default_buffer PhoenixLS.LSP.Buffer
  @default_assigns PhoenixLS.LSP.Assigns
  @default_task_supervisor PhoenixLS.LSP.TaskSupervisor
  @default_server PhoenixLS.LSP.ServerProcess

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Elixir.Supervisor.start_link(__MODULE__.Supervisor, opts,
      name: Keyword.get(opts, :name, @default_name)
    )
  end

  defmodule Supervisor do
    @moduledoc false

    use Elixir.Supervisor

    @impl true
    def init(opts) do
      buffer_name = Keyword.get(opts, :buffer_name, PhoenixLS.LSP.Runtime.default_buffer())
      assigns_name = Keyword.get(opts, :assigns_name, PhoenixLS.LSP.Runtime.default_assigns())

      task_supervisor_name =
        Keyword.get(opts, :task_supervisor_name, PhoenixLS.LSP.Runtime.default_task_supervisor())

      server_name = Keyword.get(opts, :server_name, PhoenixLS.LSP.Runtime.default_server())
      communication = Keyword.get(opts, :communication, {GenLSP.Communication.Stdio, []})
      init_args = Keyword.get(opts, :init_args, [])

      children = [
        {GenLSP.Buffer, name: buffer_name, communication: communication},
        {GenLSP.Assigns, name: assigns_name},
        {Task.Supervisor, name: task_supervisor_name},
        {PhoenixLS.LSP.Server,
         name: server_name,
         buffer: buffer_name,
         assigns: assigns_name,
         task_supervisor: task_supervisor_name,
         init_args: init_args}
      ]

      Elixir.Supervisor.init(children, strategy: :one_for_all)
    end
  end

  def default_buffer, do: @default_buffer
  def default_assigns, do: @default_assigns
  def default_task_supervisor, do: @default_task_supervisor
  def default_server, do: @default_server
end
