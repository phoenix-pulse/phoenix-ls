defmodule PhoenixLS.Index.DependencyGraphTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.{DependencyGraph, Fact}
  alias PhoenixLS.Workspace.Document

  @route_uri "file:///tmp/app/lib/app_web/router.ex"
  @component_uri "file:///tmp/app/lib/app_web/components/core_components.ex"
  @template_uri "file:///tmp/app/lib/app_web/live/page.html.heex"

  test "changed kinds ignores provenance-only changes" do
    before_facts = [
      fact(:route, "AppWeb.Router:GET:/", @route_uri, %{path: "/"}, %{document_version: 1})
    ]

    after_facts = [
      fact(:route, "AppWeb.Router:GET:/", @route_uri, %{path: "/"}, %{document_version: 2})
    ]

    assert DependencyGraph.changed_kinds(before_facts, after_facts) == MapSet.new()
  end

  test "changed kinds includes removed and added fact kinds" do
    before_facts = [
      fact(:route, "AppWeb.Router:GET:/old", @route_uri, %{path: "/old"}),
      fact(:component_attr, "AppWeb.CoreComponents.button/1:attr:label", @component_uri, %{
        name: "label",
        required: true
      })
    ]

    after_facts = [
      fact(:route, "AppWeb.Router:GET:/new", @route_uri, %{path: "/new"}),
      fact(:component_attr, "AppWeb.CoreComponents.button/1:attr:kind", @component_uri, %{
        name: "kind",
        required: false
      })
    ]

    assert DependencyGraph.changed_kinds(before_facts, after_facts) ==
             MapSet.new([:component_attr, :route])
  end

  test "affected read models are derived from changed fact kinds" do
    changed_kinds =
      MapSet.new([
        :route,
        :schema_field,
        :component_attr,
        :template,
        :live_event,
        :live_event_usage,
        :live_navigation_reference,
        :live_view_function,
        :live_view,
        :pipeline
      ])

    assert DependencyGraph.affected_read_models(changed_kinds) == [
             :components,
             :events,
             :live_views,
             :routes,
             :schemas,
             :templates
           ]
  end

  test "LiveView function changes affect the LiveView read model" do
    assert DependencyGraph.affected_read_models(MapSet.new([:live_view_function])) == [
             :live_views
           ]
  end

  test "LiveView navigation reference changes affect the LiveView read model" do
    assert DependencyGraph.affected_read_models(MapSet.new([:live_navigation_reference])) == [
             :live_views
           ]
  end

  test "semantic dependency changes affect open HEEx and Elixir diagnostics" do
    documents = [
      Document.new(
        "file:///tmp/app/lib/app_web/live/page_live.ex",
        "elixir",
        1,
        "defmodule PageLive do\nend\n"
      ),
      Document.new(@template_uri, "phoenix-heex", 1, "<.button />"),
      Document.new("file:///tmp/app/lib/app_web/live/other.html.heex", "heex", 1, "<div />")
    ]

    changed_kinds = MapSet.new([:route, :component_attr, :schema_field, :live_event])

    assert DependencyGraph.affected_diagnostic_uris(changed_kinds, documents) == [
             "file:///tmp/app/lib/app_web/live/other.html.heex",
             @template_uri,
             "file:///tmp/app/lib/app_web/live/page_live.ex"
           ]
  end

  test "LiveView navigation dependency changes affect open diagnostics" do
    documents = [
      Document.new(
        "file:///tmp/app/lib/app_web/live/page_live.ex",
        "elixir",
        1,
        "defmodule PageLive do\nend\n"
      ),
      Document.new(@template_uri, "phoenix-heex", 1, "<.link patch={~p\"/products\"} />")
    ]

    assert DependencyGraph.affected_diagnostic_uris(
             MapSet.new([:live_view_function, :live_navigation_reference]),
             documents
           ) == [
             @template_uri,
             "file:///tmp/app/lib/app_web/live/page_live.ex"
           ]
  end

  test "colocated hook changes affect open HEEx diagnostics" do
    documents = [
      Document.new(
        "file:///tmp/app/lib/app_web/live/page_live.ex",
        "elixir",
        1,
        "defmodule PageLive do\nend\n"
      ),
      Document.new(@template_uri, "phoenix-heex", 1, "<div />"),
      Document.new("file:///tmp/app/lib/app_web/live/other.html.heex", "heex", 1, "<div />")
    ]

    assert DependencyGraph.affected_diagnostic_uris(MapSet.new([:colocated_hook]), documents) == [
             "file:///tmp/app/lib/app_web/live/other.html.heex",
             @template_uri
           ]
  end

  test "template-only changes do not refresh other open HEEx diagnostics" do
    documents = [
      Document.new(@template_uri, "phoenix-heex", 1, "<.button />")
    ]

    assert DependencyGraph.affected_diagnostic_uris(MapSet.new([:template]), documents) == []
  end

  test "template changes affect open Elixir diagnostics" do
    controller_uri = "file:///tmp/app/lib/app_web/controllers/page_controller.ex"

    documents = [
      Document.new(controller_uri, "elixir", 1, "defmodule PageController do\nend\n"),
      Document.new(@template_uri, "phoenix-heex", 1, "<.button />")
    ]

    assert DependencyGraph.affected_diagnostic_uris(MapSet.new([:template]), documents) == [
             controller_uri
           ]
  end

  test "pipeline changes affect route read models and open Elixir diagnostics" do
    controller_uri = "file:///tmp/app/lib/app_web/controllers/page_controller.ex"

    documents = [
      Document.new(controller_uri, "elixir", 1, "defmodule PageController do\nend\n"),
      Document.new(@template_uri, "phoenix-heex", 1, "<div />")
    ]

    assert DependencyGraph.affected_read_models(MapSet.new([:pipeline])) == [:routes]

    assert DependencyGraph.affected_diagnostic_uris(MapSet.new([:pipeline]), documents) == [
             controller_uri
           ]
  end

  defp fact(kind, id, uri, data, provenance \\ %{source: :test}) do
    Fact.new!(
      kind: kind,
      id: id,
      uri: uri,
      range: %Range{
        start: %Position{line: 0, character: 0},
        end: %Position{line: 0, character: 1}
      },
      provenance: provenance,
      data: data
    )
  end
end
