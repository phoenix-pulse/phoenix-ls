defmodule PhoenixLS.RealProjectMatrixTest do
  use ExUnit.Case, async: false

  alias PhoenixLS.Features.PhoenixRequests
  alias PhoenixLS.Index.{Indexer, Snapshot, Store}
  alias PhoenixLS.Support.URI, as: SupportURI

  @fixtures Path.expand("../fixtures", __DIR__)
  @methods [
    "phoenix/listSchemas",
    "phoenix/listComponents",
    "phoenix/listRoutes",
    "phoenix/listTemplates",
    "phoenix/listEvents",
    "phoenix/listLiveView"
  ]

  @matrix [
    {"Phoenix 1.7 app", "phoenix_1_7_app",
     %{
       "phoenix/listSchemas" => 1,
       "phoenix/listComponents" => 1,
       "phoenix/listRoutes" => 2,
       "phoenix/listEvents" => 1,
       "phoenix/listLiveView" => 1
     }},
    {"Phoenix 1.8 app", "phoenix_1_8_app",
     %{
       "phoenix/listSchemas" => 1,
       "phoenix/listComponents" => 1,
       "phoenix/listRoutes" => 2,
       "phoenix/listEvents" => 1,
       "phoenix/listLiveView" => 1
     }},
    {"umbrella child app", Path.join(["umbrella_app", "apps", "shop"]),
     %{
       "phoenix/listSchemas" => 1,
       "phoenix/listRoutes" => 1,
       "phoenix/listLiveView" => 1
     }},
    {"LiveView-heavy app", "liveview_components_app",
     %{
       "phoenix/listSchemas" => 1,
       "phoenix/listComponents" => 1,
       "phoenix/listRoutes" => 6,
       "phoenix/listTemplates" => 4,
       "phoenix/listEvents" => 2,
       "phoenix/listLiveView" => 2
     }},
    {"broken syntax app", "broken_syntax_app", %{}},
    {"non-compiling app", "non_compiling_app", %{"phoenix/listLiveView" => 1}},
    {"missing deps app", "missing_deps_app",
     %{
       "phoenix/listRoutes" => 1,
       "phoenix/listEvents" => 1,
       "phoenix/listLiveView" => 1
     }},
    {"large stress app", "large_stress_app",
     %{
       "phoenix/listSchemas" => 1,
       "phoenix/listComponents" => 5,
       "phoenix/listRoutes" => 20,
       "phoenix/listEvents" => 10,
       "phoenix/listLiveView" => 1
     }}
  ]

  test "source-only indexing covers the real Phoenix project matrix" do
    for {label, relative_root, expected_minimums} <- @matrix do
      snapshot = index_fixture(relative_root)
      results = Map.new(@methods, &{&1, PhoenixRequests.handle(&1, snapshot)})

      for {method, minimum} <- expected_minimums do
        assert length(results[method]) >= minimum,
               "#{label} expected at least #{minimum} #{method} entries"
      end

      assert_explorer_contracts(label, results)
    end
  end

  defp index_fixture(relative_root) do
    root = Path.join(@fixtures, relative_root)
    root_uri = SupportURI.path_to_file_uri!(root)
    store = Module.concat(__MODULE__, :"Store#{System.unique_integer([:positive])}")
    indexer = Module.concat(__MODULE__, :"Indexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: store}, id: {Store, store})
    start_supervised!({Indexer, name: indexer, index_store: store}, id: {Indexer, indexer})

    assert Indexer.schedule_project(indexer, root_uri) == :ok

    assert_eventually(fn ->
      assert Store.all(store) != [] or relative_root == "broken_syntax_app"
    end)

    Snapshot.from_store(store)
  end

  defp assert_explorer_contracts(label, results) do
    Enum.each(results["phoenix/listSchemas"], &assert_schema_payload!(label, &1))
    Enum.each(results["phoenix/listComponents"], &assert_component_payload!(label, &1))
    Enum.each(results["phoenix/listRoutes"], &assert_route_payload!(label, &1))
    Enum.each(results["phoenix/listTemplates"], &assert_template_payload!(label, &1))
    Enum.each(results["phoenix/listEvents"], &assert_event_payload!(label, &1))
    Enum.each(results["phoenix/listLiveView"], &assert_live_view_payload!(label, &1))
  end

  defp assert_schema_payload!(label, payload) do
    assert_string(label, "schema.module", payload["module"])
    assert_string(label, "schema.table", payload["table"])
    assert_string(label, "schema.filePath", payload["filePath"])
    assert_location(label, "schema.location", payload["location"])
    assert is_list(payload["fields"])
    assert is_list(payload["associations"])
  end

  defp assert_component_payload!(label, payload) do
    assert_string(label, "component.module", payload["module"])
    assert_string(label, "component.name", payload["name"])
    assert_string(label, "component.filePath", payload["filePath"])
    assert_location(label, "component.location", payload["location"])
    assert is_list(payload["attributes"])
    assert is_list(payload["slots"])
  end

  defp assert_route_payload!(label, payload) do
    assert_string(label, "route.verb", payload["verb"])
    assert_string(label, "route.path", payload["path"])
    assert_string(label, "route.filePath", payload["filePath"])
    assert_location(label, "route.location", payload["location"])
    assert_string(label, "route.helperBase", payload["helperBase"])
    assert_string(label, "route.helperName", payload["helperName"])
    assert is_list(payload["helperVariants"])
    assert is_list(payload["pathParams"])
    assert is_list(payload["pipelines"])
  end

  defp assert_template_payload!(label, payload) do
    assert_string(label, "template.name", payload["name"])
    assert_string(label, "template.format", payload["format"])
    assert_string(label, "template.kind", payload["kind"])
    assert_string(label, "template.module", payload["module"])
    assert_string(label, "template.filePath", payload["filePath"])
    assert_location(label, "template.location", payload["location"])
  end

  defp assert_event_payload!(label, payload) do
    assert_string(label, "event.name", payload["name"])
    assert_string(label, "event.type", payload["type"])
    assert_string(label, "event.handler", payload["handler"])
    assert is_integer(payload["arity"])
    assert_string(label, "event.module", payload["module"])
    assert_string(label, "event.source", payload["source"])
    assert_string(label, "event.filePath", payload["filePath"])
    assert_location(label, "event.location", payload["location"])
  end

  defp assert_live_view_payload!(label, payload) do
    assert_string(label, "liveView.module", payload["module"])
    assert_string(label, "liveView.filePath", payload["filePath"])
    assert_location(label, "liveView.location", payload["location"])
    assert is_list(payload["assigns"])
    assert is_list(payload["functions"])
  end

  defp assert_string(label, field, value) do
    assert is_binary(value) and value != "", "#{label} expected #{field}"
  end

  defp assert_location(label, field, %{"line" => line, "character" => character}) do
    assert is_integer(line), "#{label} expected #{field}.line"
    assert is_integer(character), "#{label} expected #{field}.character"
  end

  defp assert_location(label, field, _value) do
    flunk("#{label} expected #{field}")
  end

  defp assert_eventually(fun, attempts_left \\ 40)

  defp assert_eventually(fun, attempts_left) do
    fun.()
  rescue
    exception in [ExUnit.AssertionError, MatchError] ->
      if attempts_left > 0 do
        Process.sleep(10)
        assert_eventually(fun, attempts_left - 1)
      else
        reraise exception, __STACKTRACE__
      end
  end
end
