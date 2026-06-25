defmodule PhoenixLS.LSP.CustomRequestAdapterTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.CustomRequestAdapter

  defmodule InnerAdapter do
    @behaviour GenLSP.Communication.Adapter

    @impl true
    def init(opts), do: {:ok, %{parent: Keyword.fetch!(opts, :parent)}}

    @impl true
    def listen(state), do: {:ok, state}

    @impl true
    def read(_state, buffer) do
      receive do
        {:inner_read, body} -> {:ok, body, buffer}
      end
    end

    @impl true
    def write(body, state) do
      send(state.parent, {:inner_write, body})
      :ok
    end
  end

  test "normalizes raw phoenix requests into workspace executeCommand requests" do
    {:ok, state} = CustomRequestAdapter.init(inner: {InnerAdapter, parent: self()})

    send(self(), {
      :inner_read,
      Jason.encode!(%{
        "id" => 7,
        "jsonrpc" => "2.0",
        "method" => "phoenix/listRoutes",
        "params" => %{"scope" => "workspace"}
      })
    })

    assert {:ok, body, ""} = CustomRequestAdapter.read(state, "")

    assert Jason.decode!(body) == %{
             "id" => 7,
             "jsonrpc" => "2.0",
             "method" => "workspace/executeCommand",
             "params" => %{
               "command" => "phoenix/listRoutes",
               "arguments" => [%{"scope" => "workspace"}]
             }
           }
  end

  test "normalizes raw controller graph phoenix requests" do
    {:ok, state} = CustomRequestAdapter.init(inner: {InnerAdapter, parent: self()})

    send(self(), {
      :inner_read,
      Jason.encode!(%{
        "id" => 8,
        "jsonrpc" => "2.0",
        "method" => "phoenix/listControllers",
        "params" => %{}
      })
    })

    assert {:ok, body, ""} = CustomRequestAdapter.read(state, "")

    assert Jason.decode!(body) == %{
             "id" => 8,
             "jsonrpc" => "2.0",
             "method" => "workspace/executeCommand",
             "params" => %{
               "command" => "phoenix/listControllers",
               "arguments" => [%{}]
             }
           }
  end

  test "passes non-phoenix requests through unchanged" do
    {:ok, state} = CustomRequestAdapter.init(inner: {InnerAdapter, parent: self()})

    request = %{
      "id" => 1,
      "jsonrpc" => "2.0",
      "method" => "initialize",
      "params" => %{"rootUri" => "file:///tmp/app"}
    }

    send(self(), {:inner_read, Jason.encode!(request)})

    assert {:ok, body, ""} = CustomRequestAdapter.read(state, "")

    assert Jason.decode!(body) == request
  end
end
