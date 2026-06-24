defmodule PhoenixLS.ApplicationTest do
  use ExUnit.Case, async: true

  test "application module exposes the OTP child specification" do
    assert PhoenixLS.Application.child_spec([]).id == PhoenixLS.Application
  end

  test "public namespace exposes a version string" do
    assert PhoenixLS.version() == "0.1.0"
  end

  test "application starts manager, project engine supervisor, registry, and fallback document store" do
    assert Process.whereis(PhoenixLS.Project.Manager)
    assert Process.whereis(PhoenixLS.Project.EngineSupervisor)
    assert Process.whereis(PhoenixLS.Project.Registry)
    assert Process.whereis(PhoenixLS.Workspace.DocumentStore)
  end
end
