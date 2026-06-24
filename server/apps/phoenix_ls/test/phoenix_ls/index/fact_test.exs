defmodule PhoenixLS.Index.FactTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  test "new! builds a fact with source location and provenance" do
    fact =
      Fact.new!(
        kind: :component,
        id: "AppWeb.Components.card/1",
        uri: @uri,
        range: range(),
        provenance: %{source: :elixir_ast, version: 3},
        data: %{module: AppWeb.Components, function: :card, arity: 1}
      )

    assert %Fact{
             kind: :component,
             id: "AppWeb.Components.card/1",
             uri: @uri,
             range: %Range{},
             provenance: %{source: :elixir_ast, version: 3},
             data: %{module: AppWeb.Components, function: :card, arity: 1}
           } = fact
  end

  test "new! defaults data to an empty map" do
    fact =
      Fact.new!(
        kind: :module,
        id: "AppWeb.PageLive",
        uri: @uri,
        range: range(),
        provenance: %{source: :elixir_ast}
      )

    assert fact.data == %{}
  end

  test "new! requires source range" do
    assert_raise ArgumentError, "index fact requires range", fn ->
      Fact.new!(
        kind: :module,
        id: "AppWeb.PageLive",
        uri: @uri,
        provenance: %{source: :elixir_ast}
      )
    end
  end

  test "new! requires provenance" do
    assert_raise ArgumentError, "index fact requires provenance", fn ->
      Fact.new!(
        kind: :module,
        id: "AppWeb.PageLive",
        uri: @uri,
        range: range()
      )
    end
  end

  test "key uses kind, uri, and id for stable replacement" do
    fact =
      Fact.new!(
        kind: :module,
        id: "AppWeb.PageLive",
        uri: @uri,
        range: range(),
        provenance: %{source: :elixir_ast}
      )

    assert Fact.key(fact) == {:module, @uri, "AppWeb.PageLive"}
  end

  defp range do
    %Range{
      start: %Position{line: 1, character: 2},
      end: %Position{line: 3, character: 4}
    }
  end
end
