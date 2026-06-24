defmodule PhoenixLS.Index.StoreTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{Fact, Store}

  @store __MODULE__.Store
  @first_uri "file:///tmp/app/lib/app_web/live/page_live.ex"
  @second_uri "file:///tmp/app/lib/app_web/components/core_components.ex"

  setup do
    start_supervised!({Store, name: @store})

    :ok
  end

  test "stores and returns facts" do
    fact = fact(:module, "AppWeb.PageLive", @first_uri)

    assert Store.put(@store, fact) == :ok
    assert Store.all(@store) == [fact]
  end

  test "filters facts by uri" do
    first = fact(:module, "AppWeb.PageLive", @first_uri)
    second = fact(:component, "AppWeb.CoreComponents.button/1", @second_uri)

    Store.put(@store, first)
    Store.put(@store, second)

    assert Store.by_uri(@store, @first_uri) == [first]
  end

  test "filters facts by kind" do
    module_fact = fact(:module, "AppWeb.PageLive", @first_uri)
    component_fact = fact(:component, "AppWeb.CoreComponents.button/1", @second_uri)

    Store.put(@store, module_fact)
    Store.put(@store, component_fact)

    assert Store.by_kind(@store, :component) == [component_fact]
  end

  test "replaces facts with the same key" do
    original =
      fact(:component, "AppWeb.CoreComponents.button/1", @second_uri, data: %{label: "original"})

    updated =
      fact(:component, "AppWeb.CoreComponents.button/1", @second_uri, data: %{label: "updated"})

    Store.put(@store, original)
    Store.put(@store, updated)

    assert Store.all(@store) == [updated]
  end

  test "deletes facts for one uri without deleting other uris" do
    first = fact(:module, "AppWeb.PageLive", @first_uri)
    second = fact(:component, "AppWeb.CoreComponents.button/1", @second_uri)

    Store.put(@store, first)
    Store.put(@store, second)

    assert Store.delete_uri(@store, @first_uri) == :ok
    assert Store.all(@store) == [second]
  end

  test "clears all indexed facts" do
    Store.put(@store, fact(:module, "AppWeb.PageLive", @first_uri))
    Store.put(@store, fact(:component, "AppWeb.CoreComponents.button/1", @second_uri))

    assert Store.clear(@store) == :ok
    assert Store.all(@store) == []
  end

  defp fact(kind, id, uri, opts \\ []) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: uri,
      range: range(),
      provenance: %{source: :test},
      data: Keyword.get(opts, :data, %{})
    )
  end

  defp range do
    %Range{
      start: %Position{line: 0, character: 0},
      end: %Position{line: 0, character: 1}
    }
  end
end
