defmodule PhoenixLS.LSP.CustomRequestAdapter do
  @moduledoc """
  Communication adapter wrapper that lets GenLSP accept Phoenix-specific requests.

  GenLSP rejects unknown client-to-server request methods before they reach the
  language server callback. This adapter keeps that behavior intact for normal
  traffic while translating raw `phoenix/*` requests into `workspace/executeCommand`,
  whose result schema can carry the explorer payloads.
  """

  @behaviour GenLSP.Communication.Adapter

  @default_inner {GenLSP.Communication.Stdio, []}

  @impl true
  def init(opts) do
    {inner, inner_opts} = Keyword.get(opts, :inner, @default_inner)
    {:ok, inner_state} = inner.init(inner_opts)

    {:ok, %{inner: inner, inner_state: inner_state}}
  end

  @impl true
  def listen(%{inner: inner, inner_state: inner_state} = state) do
    {:ok, inner_state} = inner.listen(inner_state)

    {:ok, %{state | inner_state: inner_state}}
  end

  @impl true
  def read(%{inner: inner, inner_state: inner_state}, buffer) do
    case inner.read(inner_state, buffer) do
      {:ok, body, buffer} -> {:ok, normalize_body(body), buffer}
      other -> other
    end
  end

  @impl true
  def write(body, %{inner: inner, inner_state: inner_state}) do
    inner.write(body, inner_state)
  end

  defp normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"id" => _id, "method" => "phoenix/" <> _suffix} = request} ->
        request
        |> normalize_request()
        |> Jason.encode!()

      _other ->
        body
    end
  end

  defp normalize_body(body), do: body

  defp normalize_request(%{"method" => method} = request) do
    request
    |> Map.put("method", "workspace/executeCommand")
    |> Map.put("params", %{
      "command" => method,
      "arguments" => request_arguments(request)
    })
  end

  defp request_arguments(request) do
    if Map.has_key?(request, "params") do
      [Map.get(request, "params")]
    else
      []
    end
  end
end
