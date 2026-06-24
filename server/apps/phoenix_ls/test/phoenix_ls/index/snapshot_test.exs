defmodule PhoenixLS.Index.SnapshotTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{Fact, Snapshot, Store}

  @store __MODULE__.Store

  setup do
    start_supervised!({Store, name: @store})

    :ok
  end

  test "captures all facts from a store" do
    component = fact(:component, "AppWeb.CoreComponents.button/1")
    route = fact(:route, "AppWeb.Router:live:/products:AppWeb.ProductLive.Index:index")

    Store.put(@store, component)
    Store.put(@store, route)

    snapshot = Snapshot.from_store(@store)

    assert Snapshot.all(snapshot) == [component, route]
  end

  test "reads facts by kind from the captured snapshot" do
    component = fact(:component, "AppWeb.CoreComponents.button/1")
    route = fact(:route, "AppWeb.Router:live:/products:AppWeb.ProductLive.Index:index")

    Store.put(@store, component)
    Store.put(@store, route)

    snapshot = Snapshot.from_store(@store)

    assert Snapshot.by_kind(snapshot, :component) == [component]
    assert Snapshot.by_kind(snapshot, :route) == [route]
    assert Snapshot.by_kind(snapshot, :schema) == []
  end

  test "remains immutable after the backing store changes" do
    component = fact(:component, "AppWeb.CoreComponents.button/1")
    route = fact(:route, "AppWeb.Router:live:/products:AppWeb.ProductLive.Index:index")

    Store.put(@store, component)

    snapshot = Snapshot.from_store(@store)

    Store.put(@store, route)

    assert Snapshot.all(snapshot) == [component]
    assert Snapshot.by_kind(snapshot, :route) == []
  end

  test "empty snapshot contains no facts" do
    snapshot = Snapshot.empty()

    assert Snapshot.all(snapshot) == []
    assert Snapshot.by_kind(snapshot, :component) == []
  end

  defp fact(kind, id) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: "file:///tmp/app/lib/app_web/source.ex",
      range: %Range{
        start: %Position{line: 0, character: 0},
        end: %Position{line: 0, character: 1}
      },
      provenance: %{source: :snapshot_test},
      data: %{name: id}
    )
  end
end
