defmodule PhoenixLS.PerformanceBudgetTest do
  use ExUnit.Case, async: false

  alias GenLSP.Structures.{Hover, Location}
  alias PhoenixLS.Features.{Definition, PhoenixRequests}
  alias PhoenixLS.Features.Hover, as: HoverFeature
  alias PhoenixLS.Features.Completion.Components, as: ComponentCompletion
  alias PhoenixLS.Features.Completion.Phoenix, as: PhoenixCompletion
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.{Indexer, Snapshot, Store}
  alias PhoenixLS.Support.{Positions, URI}

  @fixtures Path.expand("../fixtures", __DIR__)

  @feature_budget_ms 250
  @request_budget_ms 250
  @project_index_budget_ms 2_000
  @memory_budget_bytes 512 * 1024 * 1024
  @cursor_marker "__PHOENIX_LS_CURSOR__"

  @methods [
    "phoenix/listSchemas",
    "phoenix/listComponents",
    "phoenix/listRoutes",
    "phoenix/listTemplates",
    "phoenix/listEvents",
    "phoenix/listLiveView"
  ]

  @large_request_minimums %{
    "phoenix/listSchemas" => 1,
    "phoenix/listComponents" => 5,
    "phoenix/listRoutes" => 20,
    "phoenix/listTemplates" => 0,
    "phoenix/listEvents" => 10,
    "phoenix/listLiveView" => 1
  }

  @memory_matrix [
    {"small", "phoenix_1_7_app"},
    {"medium", "liveview_components_app"},
    {"large", "large_stress_app"}
  ]

  test "initial large project indexing reports progress within the project budget" do
    %{snapshot: snapshot, started_status: started, completed_status: completed} =
      index_fixture("large_stress_app")

    assert started["phase"] == "started"
    assert started["job"] == "project"
    assert started["rootUri"] != nil

    assert completed["phase"] == "completed"
    assert completed["job"] == "project"
    assert completed["result"] == "ok"
    assert completed["count"] >= 4
    assert completed["budgetMs"] == @project_index_budget_ms
    assert completed["durationMs"] <= @project_index_budget_ms
    refute completed["overBudget"]

    assert length(Snapshot.all(snapshot)) >= 40
  end

  test "large project warm completion, hover, and definition stay within feature budgets" do
    %{snapshot: snapshot, root: root} = index_fixture("large_stress_app")
    facts = Snapshot.all(snapshot)

    live_path =
      Path.join(root, "lib/large_stress_app_web/live/dashboard_live.ex")

    uri = URI.path_to_file_uri!(live_path)
    source = File.read!(live_path)

    {completion_source, completion_position} =
      cursor_at(source, "<.metric", "<.me#{@cursor_marker}tric")

    _warm = completion_items(uri, completion_source, completion_position, facts)

    {items, completion_ms} =
      measure_ms(fn -> completion_items(uri, completion_source, completion_position, facts) end)

    assert completion_ms <= @feature_budget_ms
    assert Enum.any?(items, &(&1.label == ".metric"))

    {hover_source, hover_position} =
      cursor_at(source, "<.metric", "<.metric#{@cursor_marker}")

    _warm = HoverFeature.hover_source(uri, hover_source, hover_position, facts)

    {hover, hover_ms} =
      measure_ms(fn -> HoverFeature.hover_source(uri, hover_source, hover_position, facts) end)

    assert hover_ms <= @feature_budget_ms
    assert %Hover{} = hover

    _warm = Definition.definition_source(uri, hover_source, hover_position, facts)

    {definition, definition_ms} =
      measure_ms(fn -> Definition.definition_source(uri, hover_source, hover_position, facts) end)

    assert definition_ms <= @feature_budget_ms
    assert %Location{uri: definition_uri} = definition
    assert String.ends_with?(definition_uri, "/core_components.ex")
  end

  test "large project explorer requests stay within budgets and stress count floors" do
    %{snapshot: snapshot} = index_fixture("large_stress_app")

    for method <- @methods do
      {payloads, duration_ms} = measure_ms(fn -> PhoenixRequests.handle(method, snapshot) end)

      assert duration_ms <= @request_budget_ms,
             "#{method} took #{duration_ms}ms, expected <= #{@request_budget_ms}ms"

      assert length(payloads) >= Map.fetch!(@large_request_minimums, method),
             "#{method} returned too few payloads"
    end
  end

  test "small, medium, and large fixtures stay within memory measurement envelope" do
    measurements =
      for {label, fixture} <- @memory_matrix do
        compact_memory()
        before_bytes = :erlang.memory(:total)

        %{snapshot: snapshot} = index_fixture(fixture)

        compact_memory()
        after_bytes = :erlang.memory(:total)
        delta_bytes = max(after_bytes - before_bytes, 0)

        %{
          label: label,
          fixture: fixture,
          facts: length(Snapshot.all(snapshot)),
          delta_bytes: delta_bytes
        }
      end

    for measurement <- measurements do
      assert measurement.facts > 0

      assert measurement.delta_bytes <= @memory_budget_bytes,
             "#{measurement.label} fixture #{measurement.fixture} used #{measurement.delta_bytes} bytes"
    end
  end

  defp index_fixture(relative_root) do
    root = Path.join(@fixtures, relative_root)
    root_uri = URI.path_to_file_uri!(root)
    store = Module.concat(__MODULE__, :"Store#{System.unique_integer([:positive])}")
    indexer = Module.concat(__MODULE__, :"Indexer#{System.unique_integer([:positive])}")

    start_supervised!({Store, name: store}, id: {Store, store})

    start_supervised!(
      {Indexer,
       name: indexer,
       index_store: store,
       status_target: self(),
       performance_budgets_ms: %{project: @project_index_budget_ms}},
      id: {Indexer, indexer}
    )

    assert Indexer.schedule_project(indexer, root_uri) == :ok

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "started",
                      "job" => "project",
                      "rootUri" => ^root_uri
                    } = started_status},
                   1_000

    assert_receive {:phoenix_ls_status,
                    %{
                      "kind" => "indexing",
                      "phase" => "completed",
                      "job" => "project",
                      "rootUri" => ^root_uri
                    } = completed_status},
                   5_000

    assert_eventually(fn -> assert Store.all(store) != [] end)

    %{
      root: root,
      snapshot: Snapshot.from_store(store),
      started_status: started_status,
      completed_status: completed_status
    }
  end

  defp completion_items(uri, source, position, facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      ComponentCompletion.complete(source, position, facts) ++
        PhoenixCompletion.complete(context, facts) ++
        PhoenixCompletion.complete(uri, source, position, facts)
    else
      :error -> []
    end
  end

  defp cursor_at(source, needle, marked_needle) do
    marked_source = String.replace(source, needle, marked_needle, global: false)

    if marked_source == source do
      raise ArgumentError, "missing cursor needle #{inspect(needle)}"
    end

    source_and_position(marked_source)
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, @cursor_marker, "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, position}
  end

  defp marker_offset!(marked_source) do
    marked_source
    |> :binary.matches(@cursor_marker)
    |> case do
      [{offset, marker_size}] when marker_size == byte_size(@cursor_marker) -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end

  defp measure_ms(fun) when is_function(fun, 0) do
    started_at = System.monotonic_time()
    result = fun.()

    duration_ms =
      started_at
      |> Kernel.then(&(System.monotonic_time() - &1))
      |> System.convert_time_unit(:native, :millisecond)

    {result, duration_ms}
  end

  defp compact_memory do
    :erlang.garbage_collect()
    :erlang.garbage_collect(self())
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
