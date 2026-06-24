defmodule PhoenixLS.Application do
  @moduledoc false

  use Application

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, [:normal, args]},
      type: :supervisor
    }
  end

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: PhoenixLS.Project.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: PhoenixLS.Project.EngineSupervisor},
      PhoenixLS.Project.Manager,
      PhoenixLS.Workspace.DocumentStore
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: PhoenixLS.Supervisor
    )
  end
end
