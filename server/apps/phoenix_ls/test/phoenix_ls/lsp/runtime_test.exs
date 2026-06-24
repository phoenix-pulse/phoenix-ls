defmodule PhoenixLS.LSP.RuntimeTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.LSP.Runtime

  defmodule SilentCommunication do
    @behaviour GenLSP.Communication.Adapter

    @impl true
    def init(opts), do: {:ok, %{parent: Keyword.fetch!(opts, :parent)}}

    @impl true
    def listen(state), do: {:ok, state}

    @impl true
    def read(_state, _buffer), do: :eof

    @impl true
    def write(body, state) do
      send(state.parent, {:runtime_write, body})
      :ok
    end
  end

  defmodule ScriptedCommunication do
    @behaviour GenLSP.Communication.Adapter

    @impl true
    def init(opts), do: {:ok, %{parent: Keyword.fetch!(opts, :parent)}}

    @impl true
    def listen(state) do
      send(state.parent, {:runtime_reader, self()})
      {:ok, state}
    end

    @impl true
    def read(_state, buffer) do
      receive do
        {:client_packet, body} -> {:ok, Jason.encode!(body), buffer}
      end
    end

    @impl true
    def write(body, state) do
      send(state.parent, {:runtime_packet, Jason.decode!(body)})
      :ok
    end
  end

  test "defaults runtime communication to the custom request adapter" do
    assert {PhoenixLS.LSP.CustomRequestAdapter, opts} = Runtime.default_communication()
    assert Keyword.fetch!(opts, :inner) == {GenLSP.Communication.Stdio, []}
  end

  test "starts the GenLSP runtime processes with configured names" do
    suffix = System.unique_integer([:positive])
    runtime_name = :"#{__MODULE__}.Runtime#{suffix}"
    buffer_name = :"#{__MODULE__}.Buffer#{suffix}"
    assigns_name = :"#{__MODULE__}.Assigns#{suffix}"
    task_supervisor_name = :"#{__MODULE__}.TaskSupervisor#{suffix}"
    server_name = :"#{__MODULE__}.Server#{suffix}"

    assert {:ok, runtime} =
             Runtime.start_link(
               name: runtime_name,
               buffer_name: buffer_name,
               assigns_name: assigns_name,
               task_supervisor_name: task_supervisor_name,
               server_name: server_name,
               communication: {SilentCommunication, parent: self()},
               init_args: [exit_handler: fn _code -> :ok end]
             )

    assert Process.whereis(runtime_name) == runtime
    assert is_pid(Process.whereis(buffer_name))
    assert is_pid(Process.whereis(assigns_name))
    assert is_pid(Process.whereis(task_supervisor_name))
    assert is_pid(Process.whereis(server_name))
  end

  test "runtime handles raw phoenix requests through the communication adapter" do
    suffix = System.unique_integer([:positive])
    runtime_name = :"#{__MODULE__}.RawRuntime#{suffix}"
    buffer_name = :"#{__MODULE__}.RawBuffer#{suffix}"
    assigns_name = :"#{__MODULE__}.RawAssigns#{suffix}"
    task_supervisor_name = :"#{__MODULE__}.RawTaskSupervisor#{suffix}"
    server_name = :"#{__MODULE__}.RawServer#{suffix}"

    assert {:ok, _runtime} =
             Runtime.start_link(
               name: runtime_name,
               buffer_name: buffer_name,
               assigns_name: assigns_name,
               task_supervisor_name: task_supervisor_name,
               server_name: server_name,
               communication:
                 {PhoenixLS.LSP.CustomRequestAdapter,
                  inner: {ScriptedCommunication, parent: self()}},
               init_args: [exit_handler: fn _code -> :ok end]
             )

    assert_receive {:runtime_reader, reader}, 500

    send(reader, {
      :client_packet,
      %{
        "id" => 7,
        "jsonrpc" => "2.0",
        "method" => "phoenix/listSchemas",
        "params" => %{}
      }
    })

    assert_receive {:runtime_packet, %{"id" => 7, "jsonrpc" => "2.0", "result" => []}}, 500
  end
end
