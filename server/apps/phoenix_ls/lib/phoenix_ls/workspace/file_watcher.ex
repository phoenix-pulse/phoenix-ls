defmodule PhoenixLS.Workspace.FileWatcher do
  @moduledoc """
  Optional file-system watcher that forwards events into project indexing.
  """

  use GenServer

  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.FileEvents

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl true
  def init(opts) do
    dirs = Keyword.get(opts, :dirs, [])
    project_manager = Keyword.get(opts, :project_manager, Manager)
    file_system = Keyword.get(opts, :file_system, FileSystem)
    file_system_opts = Keyword.get(opts, :file_system_opts, [])

    state = %{
      dirs: dirs,
      file_system: file_system,
      file_system_worker: nil,
      project_manager: project_manager
    }

    {:ok, start_file_system(state, file_system_opts)}
  end

  @impl true
  def handle_info({:file_event, _worker, {path, events}}, state) do
    :ok = FileEvents.handle_file_system_event(state.project_manager, path, events)

    {:noreply, state}
  end

  def handle_info({:file_event, _worker, :stop}, state) do
    {:noreply, %{state | file_system_worker: nil}}
  end

  defp start_file_system(%{dirs: []} = state, _file_system_opts), do: state

  defp start_file_system(state, file_system_opts) do
    opts = Keyword.merge(file_system_opts, dirs: state.dirs)

    with {:ok, worker} <- state.file_system.start_link(opts),
         :ok <- state.file_system.subscribe(worker) do
      %{state | file_system_worker: worker}
    else
      _unavailable -> state
    end
  end
end
