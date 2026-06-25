defmodule PhoenixLS.LSP.ModeTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.Mode

  test "resolves automatic mode from Expert detection" do
    assert Mode.resolve(:auto, true) == :companion
    assert Mode.resolve(:auto, false) == :full
  end

  test "resolves explicit modes without detection changes" do
    assert Mode.resolve(:companion, false) == :companion
    assert Mode.resolve(:full, true) == :full
  end

  test "parses supported atom modes" do
    assert Mode.parse(:auto) == :auto
    assert Mode.parse(:companion) == :companion
    assert Mode.parse(:full) == :full
  end

  test "parses supported string modes case-insensitively with trimming" do
    assert Mode.parse(" auto ") == :auto
    assert Mode.parse("COMPANION") == :companion
    assert Mode.parse("\tFull\n") == :full
  end

  test "defaults unknown modes to auto" do
    assert Mode.parse(:unknown) == :auto
    assert Mode.parse("source-only") == :auto
    assert Mode.parse(nil) == :auto
  end
end
