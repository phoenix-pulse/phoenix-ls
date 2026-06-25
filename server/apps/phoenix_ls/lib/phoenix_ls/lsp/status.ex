defmodule PhoenixLS.LSP.Status do
  @moduledoc """
  Builds and publishes structured PhoenixLS status payloads.
  """

  alias GenLSP.LSP
  alias PhoenixLS.LSP.StatusNotification

  @spec publish(LSP.t(), map()) :: :ok
  def publish(%LSP{} = lsp, payload) when is_map(payload) do
    GenLSP.notify(lsp, %StatusNotification{params: payload})
  end

  @spec indexing_started(keyword()) :: map()
  def indexing_started(opts) when is_list(opts) do
    %{
      "kind" => "indexing",
      "phase" => "started",
      "job" => job_string(Keyword.fetch!(opts, :job))
    }
    |> put_optional("rootUri", Keyword.get(opts, :root_uri))
    |> put_optional("uri", Keyword.get(opts, :uri))
  end

  @spec indexing_completed(keyword()) :: map()
  def indexing_completed(opts) when is_list(opts) do
    opts
    |> indexing_started()
    |> Map.put("phase", "completed")
    |> put_optional("result", result_string(Keyword.get(opts, :result)))
    |> put_optional("count", Keyword.get(opts, :count))
    |> put_optional("durationMs", Keyword.get(opts, :duration_ms))
    |> put_optional("budgetMs", Keyword.get(opts, :budget_ms))
    |> put_optional("overBudget", Keyword.get(opts, :over_budget?))
  end

  @spec compilation_started(keyword()) :: map()
  def compilation_started(opts) when is_list(opts) do
    %{
      "kind" => "compilation",
      "phase" => "started"
    }
    |> put_optional("rootUri", Keyword.get(opts, :root_uri))
  end

  @spec compilation_completed(keyword()) :: map()
  def compilation_completed(opts) when is_list(opts) do
    opts
    |> compilation_started()
    |> Map.put("phase", "completed")
    |> put_optional("result", result_string(Keyword.get(opts, :result)))
    |> put_optional("sourceOnly", Keyword.get(opts, :source_only?))
  end

  @spec project_degraded(String.t(), term(), keyword()) :: map()
  def project_degraded(root_uri, reason, opts \\ []) when is_binary(root_uri) do
    %{
      "kind" => "project",
      "state" => "degraded",
      "rootUri" => root_uri,
      "sourceOnly" => Keyword.get(opts, :source_only?, true),
      "reason" => inspect(reason)
    }
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp job_string(job) when is_atom(job), do: Atom.to_string(job)
  defp job_string(job) when is_binary(job), do: job

  defp result_string(nil), do: nil
  defp result_string(result) when is_atom(result), do: Atom.to_string(result)
  defp result_string({:error, reason}), do: "error: #{inspect(reason)}"
  defp result_string(result), do: inspect(result)
end
