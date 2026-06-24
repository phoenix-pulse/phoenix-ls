defmodule PhoenixLS.Support.Telemetry do
  @moduledoc """
  PhoenixLS telemetry helpers.
  """

  @prefix [:phoenix_ls]

  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements \\ %{}, metadata \\ %{}) when is_list(event) do
    :telemetry.execute(@prefix ++ event, measurements, metadata)
  end

  @spec span([atom()], map(), (-> {term(), map()})) :: term()
  def span(event, metadata, fun) when is_list(event) and is_function(fun, 0) do
    :telemetry.span(@prefix ++ event, metadata, fun)
  end
end
