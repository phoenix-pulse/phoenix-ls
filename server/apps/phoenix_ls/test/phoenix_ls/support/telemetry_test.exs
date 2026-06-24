defmodule PhoenixLS.Support.TelemetryTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Support.Telemetry

  test "executes telemetry events under the phoenix_ls prefix" do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach_many(
      handler_id,
      [[:phoenix_ls, :unit, :event]],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert Telemetry.execute([:unit, :event], %{count: 1}, %{source: :test}) == :ok

    assert_receive {:telemetry_event, [:phoenix_ls, :unit, :event], %{count: 1}, %{source: :test}}
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry_event, event, measurements, metadata})
  end
end
