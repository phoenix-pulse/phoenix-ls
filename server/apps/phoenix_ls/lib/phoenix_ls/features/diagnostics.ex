defmodule PhoenixLS.Features.Diagnostics do
  @moduledoc """
  Phoenix diagnostics derived from parsed HEEx documents and indexed facts.
  """

  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.{ComponentLookup, Facts, TemplateFacts}

  alias PhoenixLS.Features.Diagnostics.{
    ColocatedAssets,
    Components,
    Events,
    HeexStructure,
    Hooks,
    Navigation,
    PhoenixAttrs,
    RouteHelpers,
    Routes,
    Streams,
    Templates,
    Uploads
  }

  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.Tag
  alias PhoenixLS.Index.Fact

  @spec diagnostics(Document.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(%Document{tags: tags} = document, facts) when is_list(facts) do
    indexes = indexes(facts, nil)

    structure_results = HeexStructure.diagnostics(document)
    tag_results = Enum.flat_map(tags, &tag_diagnostics(&1, indexes, tags))

    structure_results ++ tag_results ++ Uploads.diagnostics(tags, facts)
  end

  @spec diagnostics(String.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    Templates.diagnostics(uri, facts) ++
      RouteHelpers.diagnostics(uri, facts) ++
      Navigation.diagnostics(uri, facts) ++
      Hooks.diagnostics(uri, facts) ++
      ColocatedAssets.diagnostics(uri, facts)
  end

  @spec diagnostics(String.t(), Document.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, %Document{tags: tags} = document, facts)
      when is_binary(uri) and is_list(facts) do
    indexes = indexes(facts, uri)

    structure_results = HeexStructure.diagnostics(document)
    tag_results = Enum.flat_map(tags, &tag_diagnostics(&1, indexes, tags))

    structure_results ++
      tag_results ++
      Hooks.diagnostics(uri, facts) ++
      Navigation.diagnostics(uri, tags, facts) ++
      Uploads.diagnostics(uri, tags, facts) ++
      ColocatedAssets.diagnostics(uri, facts)
  end

  defp tag_diagnostics(%Tag{} = tag, indexes, tags) do
    Components.diagnostics(tag, indexes, tags) ++
      PhoenixAttrs.diagnostics(tag) ++
      Routes.diagnostics(tag, indexes.routes) ++
      Events.diagnostics(tag, indexes.events, indexes.event_names) ++
      Streams.diagnostics(tag, tags)
  end

  defp indexes(facts, uri) do
    event_facts = event_facts_for_uri(facts, uri)

    %{
      facts: facts,
      module: ComponentLookup.module_for_uri(facts, uri),
      attrs_by_component:
        facts
        |> Facts.by_kind(:component_attr)
        |> Enum.group_by(& &1.data.component),
      attrs_by_slot:
        facts
        |> Facts.by_kind(:component_slot_attr)
        |> Enum.group_by(& &1.data.slot),
      slots_by_component:
        facts
        |> Facts.by_kind(:component_slot)
        |> Enum.group_by(& &1.data.component),
      events:
        event_facts
        |> MapSet.new(& &1.data.event),
      event_names:
        event_facts
        |> Enum.map(& &1.data.event)
        |> Enum.uniq()
        |> Enum.sort(),
      routes:
        facts
        |> Facts.by_kind(:route)
        |> MapSet.new(& &1.data.path)
    }
  end

  defp event_facts_for_uri(facts, nil), do: Facts.by_kind(facts, :live_event)

  defp event_facts_for_uri(facts, uri) do
    case TemplateFacts.module_for_uri(facts, uri) do
      {:ok, module} ->
        facts
        |> Facts.by_kind(:live_event)
        |> Enum.filter(&(&1.data.module == module))

      :error ->
        Facts.by_kind(facts, :live_event)
    end
  end
end
