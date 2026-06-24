defmodule PhoenixLS.ApplicationTest do
  use ExUnit.Case, async: true

  test "application module exposes the OTP child specification" do
    assert PhoenixLS.Application.child_spec([]).id == PhoenixLS.Application
  end

  test "public namespace exposes a version string" do
    assert PhoenixLS.version() == "0.1.0"
  end
end
