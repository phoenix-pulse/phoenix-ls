defmodule PhoenixLS.Index.DependencyGraph do
  @moduledoc """
  Pure dependency mapping from changed indexed facts to affected project read models.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Workspace.Document

  @read_model_order [:components, :events, :live_views, :routes, :schemas, :templates]

  @read_model_by_kind %{
    component: :components,
    component_attr: :components,
    component_slot: :components,
    component_slot_attr: :components,
    component_alias: :components,
    component_import: :components,
    live_event: :events,
    live_event_usage: :events,
    live_view: :live_views,
    live_view_function: :live_views,
    assign: :live_views,
    route: :routes,
    schema: :schemas,
    schema_association: :schemas,
    schema_field: :schemas,
    template: :templates,
    template_reference: :templates
  }

  @heex_diagnostic_dependency_kinds MapSet.new([
                                      :component,
                                      :component_attr,
                                      :component_slot,
                                      :component_slot_attr,
                                      :live_event,
                                      :live_event_usage,
                                      :route,
                                      :schema,
                                      :schema_association,
                                      :schema_field
                                    ])

  @elixir_diagnostic_dependency_kinds MapSet.new([
                                        :template,
                                        :template_reference
                                      ])

  @spec changed_kinds([Fact.t()], [Fact.t()]) :: MapSet.t(atom())
  def changed_kinds(before_facts, after_facts)
      when is_list(before_facts) and is_list(after_facts) do
    before_set = comparable_set(before_facts)
    after_set = comparable_set(after_facts)

    before_set
    |> MapSet.difference(after_set)
    |> MapSet.union(MapSet.difference(after_set, before_set))
    |> Enum.map(&comparable_kind/1)
    |> MapSet.new()
  end

  @spec affected_read_models(MapSet.t(atom()) | [atom()]) :: [atom()]
  def affected_read_models(changed_kinds) do
    affected =
      changed_kinds
      |> normalize_kinds()
      |> Enum.flat_map(fn kind ->
        case Map.fetch(@read_model_by_kind, kind) do
          {:ok, read_model} -> [read_model]
          :error -> []
        end
      end)
      |> MapSet.new()

    Enum.filter(@read_model_order, &MapSet.member?(affected, &1))
  end

  @spec affected_diagnostic_uris(MapSet.t(atom()) | [atom()], [Document.t()]) :: [String.t()]
  def affected_diagnostic_uris(changed_kinds, documents) when is_list(documents) do
    changed_kinds = normalize_kinds(changed_kinds)

    documents
    |> Enum.filter(&affected_diagnostic_document?(changed_kinds, &1))
    |> Enum.map(& &1.uri)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp comparable_set(facts) do
    MapSet.new(facts, &comparable_fact/1)
  end

  defp comparable_fact(%Fact{} = fact) do
    {fact.kind, fact.uri, fact.id, fact.range, fact.data}
  end

  defp comparable_kind({kind, _uri, _id, _range, _data}), do: kind

  defp normalize_kinds(%MapSet{} = changed_kinds), do: changed_kinds
  defp normalize_kinds(changed_kinds) when is_list(changed_kinds), do: MapSet.new(changed_kinds)

  defp affected_diagnostic_document?(changed_kinds, %Document{} = document) do
    (not MapSet.disjoint?(changed_kinds, @heex_diagnostic_dependency_kinds) and
       heex_document?(document)) or
      (not MapSet.disjoint?(changed_kinds, @elixir_diagnostic_dependency_kinds) and
         elixir_document?(document))
  end

  defp heex_document?(%Document{language_id: language_id, uri: uri}) do
    language_id in ["phoenix-heex", "heex"] or
      String.ends_with?(uri, [".heex", ".html.heex"])
  end

  defp elixir_document?(%Document{language_id: "elixir"}), do: true
  defp elixir_document?(%Document{uri: uri}), do: String.ends_with?(uri, ".ex")
end
