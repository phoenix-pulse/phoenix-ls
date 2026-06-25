defmodule PhoenixLS.Features.PhoenixRequests.Controllers do
  @moduledoc """
  Payload builder for controller explorer graph requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @spec list(term()) :: [map()]
  def list(snapshot) do
    facts = controller_graph_facts(snapshot)
    templates_by_uri = Map.new(facts.templates, &{&1.uri, &1})
    routes_by_action = group_routes_by_action(facts.routes)
    actions_by_module = Enum.group_by(facts.actions, & &1.data.module)
    renders_by_action = group_by_module_action(facts.renders, & &1.data.action)
    assigns_by_action = group_by_module_action(facts.assigns, & &1.data.action)
    layouts_by_action = group_by_module_action(facts.layouts, & &1.data.action)
    plug_assigns_by_module = Enum.group_by(facts.plug_assigns, & &1.data.module)

    facts.controllers
    |> Enum.map(fn controller ->
      controller_payload(
        controller,
        Map.get(actions_by_module, controller.data.module, []),
        Map.get(plug_assigns_by_module, controller.data.module, []),
        routes_by_action,
        renders_by_action,
        assigns_by_action,
        layouts_by_action,
        templates_by_uri
      )
    end)
    |> Enum.sort_by(& &1["module"])
  end

  defp controller_graph_facts(snapshot) do
    %{
      controllers: Payload.facts_by_kind(snapshot, :controller),
      actions: Payload.facts_by_kind(snapshot, :controller_action),
      renders: Payload.facts_by_kind(snapshot, :controller_render),
      assigns: Payload.facts_by_kind(snapshot, :controller_assign),
      layouts: Payload.facts_by_kind(snapshot, :controller_layout),
      plug_assigns: Payload.facts_by_kind(snapshot, :controller_plug_assign),
      routes: Payload.facts_by_kind(snapshot, :route),
      templates: Payload.facts_by_kind(snapshot, :template)
    }
  end

  defp controller_payload(
         %Fact{} = controller,
         actions,
         plug_assigns,
         routes_by_action,
         renders_by_action,
         assigns_by_action,
         layouts_by_action,
         templates_by_uri
       ) do
    module = controller.data.module

    %{
      "name" => module,
      "module" => module,
      "filePath" => Payload.file_path(controller.uri),
      "location" => Payload.location(controller),
      "actions" =>
        action_payloads(
          actions,
          routes_by_action,
          renders_by_action,
          assigns_by_action,
          layouts_by_action,
          templates_by_uri
        ),
      "plugAssigns" => plug_assign_payloads(plug_assigns)
    }
  end

  defp action_payloads(
         actions,
         routes_by_action,
         renders_by_action,
         assigns_by_action,
         layouts_by_action,
         templates_by_uri
       ) do
    actions
    |> Enum.map(fn action ->
      key = {action.data.module, action.data.action}
      routes = route_payloads(Map.get(routes_by_action, key, []))

      %{
        "name" => action.data.action,
        "arity" => action.data.arity,
        "filePath" => Payload.file_path(action.uri),
        "location" => Payload.location(action),
        "route" => List.first(routes),
        "routes" => routes,
        "renders" => render_payloads(Map.get(renders_by_action, key, []), templates_by_uri),
        "assigns" => assign_payloads(Map.get(assigns_by_action, key, [])),
        "layouts" => layout_payloads(Map.get(layouts_by_action, key, []))
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp route_payloads(routes) do
    routes
    |> Enum.map(&Payload.route_payload/1)
    |> Enum.sort_by(&{&1["path"], &1["verb"]})
  end

  defp render_payloads(renders, templates_by_uri) do
    renders
    |> Enum.map(&render_payload(&1, templates_by_uri))
    |> Enum.sort_by(&{&1["template"], &1["format"], location_sort(&1["location"])})
  end

  defp render_payload(%Fact{} = render, templates_by_uri) do
    target = render_target(render, templates_by_uri)
    candidate_uris = Map.get(render.data, :candidate_uris, [])

    %{
      "template" => render.data.template,
      "format" => render.data.format,
      "candidateTemplatePaths" => Enum.map(candidate_uris, &Payload.file_path/1),
      "assigns" => Map.get(render.data, :assigns, []),
      "confidence" => Payload.confidence_string(Map.get(render.data, :confidence)),
      "filePath" => Payload.file_path(render.uri),
      "location" => Payload.location(render)
    }
    |> Payload.maybe_put("templatePath", template_path(target))
    |> Payload.maybe_put("templateLocation", template_location(target))
  end

  defp render_target(%Fact{} = render, templates_by_uri) do
    render.data
    |> Map.get(:candidate_uris, [])
    |> Enum.find_value(&Map.get(templates_by_uri, &1))
  end

  defp template_path(nil), do: nil
  defp template_path(%Fact{} = template), do: Payload.file_path(template.uri)

  defp template_location(nil), do: nil
  defp template_location(%Fact{} = template), do: Payload.location(template)

  defp assign_payloads(assigns) do
    assigns
    |> Enum.map(fn assign ->
      %{
        "name" => assign.data.name,
        "source" => Atom.to_string(assign.data.source),
        "confidence" => Payload.confidence_string(assign.data.confidence),
        "filePath" => Payload.file_path(assign.uri),
        "location" => Payload.location(assign)
      }
    end)
    |> Enum.sort_by(&{&1["name"], &1["source"], location_sort(&1["location"])})
  end

  defp layout_payloads(layouts) do
    layouts
    |> Enum.map(fn layout ->
      %{
        "name" => layout.data.layout,
        "layout" => layout.data.layout,
        "source" => Atom.to_string(layout.data.source),
        "confidence" => Payload.confidence_string(layout.data.confidence),
        "filePath" => Payload.file_path(layout.uri),
        "location" => Payload.location(layout)
      }
    end)
    |> Enum.sort_by(&{&1["name"], location_sort(&1["location"])})
  end

  defp plug_assign_payloads(plug_assigns) do
    plug_assigns
    |> Enum.map(fn plug_assign ->
      %{
        "plug" => plug_assign.data.plug,
        "name" => plug_assign.data.name,
        "confidence" => Payload.confidence_string(plug_assign.data.confidence),
        "filePath" => Payload.file_path(plug_assign.uri),
        "location" => Payload.location(plug_assign)
      }
    end)
    |> Enum.sort_by(&{&1["plug"], &1["name"], location_sort(&1["location"])})
  end

  defp group_by_module_action(facts, action_fun) do
    facts
    |> Enum.reject(&(action_fun.(&1) in [nil, ""]))
    |> Enum.group_by(&{&1.data.module, action_fun.(&1)})
  end

  defp group_routes_by_action(routes) do
    routes
    |> Enum.reject(&(route_action(&1) in [nil, ""]))
    |> Enum.group_by(&{&1.data.plug, route_action(&1)})
  end

  defp route_action(%Fact{} = fact), do: Payload.optional_atom_string(Map.get(fact.data, :action))

  defp location_sort(%{"line" => line, "character" => character}), do: {line, character}
  defp location_sort(_location), do: {0, 0}
end
