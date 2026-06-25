defmodule PhoenixLS.FixturesTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.{Locator, Metadata}
  alias PhoenixLS.Support.URI, as: SupportURI

  @fixtures Path.expand("../fixtures", __DIR__)

  test "includes reusable Phoenix project fixture shapes" do
    for name <- [
          "phoenix_1_7_app",
          "phoenix_1_8_app",
          "liveview_components_app",
          "broken_syntax_app",
          "non_compiling_app",
          "missing_deps_app",
          "large_stress_app"
        ] do
      root = fixture(name)

      assert File.dir?(root)
      assert File.regular?(Path.join(root, "mix.exs"))
      assert File.regular?(Path.join(root, "lib/#{name}_web/router.ex"))
    end
  end

  test "Phoenix version fixtures declare their target Phoenix versions" do
    assert fixture("phoenix_1_7_app")
           |> Path.join("mix.exs")
           |> File.read!()
           |> String.contains?("~> 1.7")

    assert fixture("phoenix_1_8_app")
           |> Path.join("mix.exs")
           |> File.read!()
           |> String.contains?("~> 1.8")
  end

  test "component fixture includes components, slots, live views, schemas, and templates" do
    root = fixture("liveview_components_app")

    assert File.regular?(
             Path.join(root, "lib/liveview_components_app_web/components/core_components.ex")
           )

    assert File.regular?(Path.join(root, "lib/liveview_components_app_web/live/page_live.ex"))
    assert File.regular?(Path.join(root, "lib/liveview_components_app/catalog/product.ex"))

    assert File.regular?(
             Path.join(
               root,
               "lib/liveview_components_app_web/controllers/page_html/index.html.heex"
             )
           )
  end

  test "umbrella fixture locates child app and engine metadata detects Phoenix dependency" do
    umbrella_root = fixture("umbrella_app")
    child_root = Path.join([umbrella_root, "apps", "shop"])
    child_file = Path.join([child_root, "lib", "shop_web", "router.ex"])

    assert {:ok, result} = Locator.locate(SupportURI.path_to_file_uri!(child_file))
    assert result.root_path == child_root
    assert result.umbrella_root_path == umbrella_root

    metadata = start_supervised!({Metadata, root_uri: result.root_uri})
    assert Metadata.fetch(metadata).phoenix? == true
  end

  test "broken and non-compiling fixtures exercise different degraded modes" do
    broken =
      Path.join(fixture("broken_syntax_app"), "lib/broken_syntax_app_web/live/broken_live.ex")

    non_compiling =
      Path.join(fixture("non_compiling_app"), "lib/non_compiling_app_web/live/page_live.ex")

    assert File.read!(broken) |> String.contains?("def render(assigns) do")
    assert File.read!(non_compiling) |> String.contains?("MissingDependency.call()")
  end

  test "missing dependency and large stress fixtures cover project-matrix edge cases" do
    missing_deps_mix = Path.join(fixture("missing_deps_app"), "mix.exs")
    stress_router = Path.join(fixture("large_stress_app"), "lib/large_stress_app_web/router.ex")

    stress_live =
      Path.join(fixture("large_stress_app"), "lib/large_stress_app_web/live/dashboard_live.ex")

    assert File.read!(missing_deps_mix) |> String.contains?(":missing_phoenix_dep")
    assert File.read!(stress_router) |> String.contains?("resources(\"/orders\"")
    assert File.read!(stress_live) |> String.contains?("def handle_event(\"refresh-9\"")
  end

  defp fixture(name), do: Path.join(@fixtures, name)
end
