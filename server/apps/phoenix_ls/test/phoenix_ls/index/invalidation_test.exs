defmodule PhoenixLS.Index.InvalidationTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{Fact, Invalidation, Store}

  @store __MODULE__.Store
  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  setup do
    start_supervised!({Store, name: @store})
    :ok
  end

  test "invalidates all facts for one uri" do
    Store.put(@store, fact(:module, "AppWeb.PageLive", @uri))
    Store.put(@store, fact(:function, "AppWeb.PageLive.mount/3", @uri))
    Store.put(@store, fact(:module, "AppWeb.OtherLive", "file:///tmp/app/lib/other.ex"))

    assert Invalidation.invalidate_uri(@store, @uri) == :ok

    assert Store.by_uri(@store, @uri) == []
    assert Enum.map(Store.all(@store), & &1.id) == ["AppWeb.OtherLive"]
  end

  defp fact(kind, id, uri) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: uri,
      range: %Range{
        start: %Position{line: 0, character: 0},
        end: %Position{line: 0, character: 1}
      },
      provenance: %{source: :test}
    )
  end
end
