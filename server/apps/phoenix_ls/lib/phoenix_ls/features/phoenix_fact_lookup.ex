defmodule PhoenixLS.Features.PhoenixFactLookup do
  @moduledoc """
  Resolves cursor contexts to indexed Phoenix facts.
  """

  alias PhoenixLS.Features.{AssignAccess, ComponentLookup}
  alias PhoenixLS.Features.Completion.SchemaFacts
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec cursor_fact(CursorContext.t(), [Fact.t()]) :: Fact.t() | nil
  def cursor_fact(%CursorContext{kind: :tag_name, prefix: tag}, facts) do
    ComponentLookup.component_for_tag(tag, facts)
  end

  def cursor_fact(
        %CursorContext{kind: :attribute_name, tag: tag, prefix: prefix},
        facts
      ) do
    ComponentLookup.component_attr_for_tag(tag, prefix, facts)
  end

  def cursor_fact(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    cond do
      String.starts_with?(prefix, "~p\"") or String.starts_with?(prefix, "~p'") ->
        find_route(facts, route_path_prefix(prefix))

      String.starts_with?(prefix, "Routes.") ->
        find_route_helper(facts, route_helper_prefix(prefix))

      String.starts_with?(prefix, "@form[:") ->
        find_schema_field(facts, form_field_prefix(prefix))

      assign_property = find_assign_schema_property(facts, prefix) ->
        assign_property

      String.starts_with?(prefix, "@") ->
        find_assign(facts, String.trim_leading(prefix, "@"))

      true ->
        nil
    end
  end

  def cursor_fact(
        %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
        facts
      ) do
    find_live_event(facts, prefix)
  end

  def cursor_fact(_context, _facts), do: nil

  defp find_route(facts, path_prefix) do
    Enum.find(facts, &(&1.kind == :route and String.starts_with?(&1.data.path, path_prefix)))
  end

  defp find_route_helper(facts, helper_prefix) do
    Enum.find(facts, &route_helper_match?(&1, helper_prefix))
  end

  defp route_helper_match?(%Fact{kind: :route, data: %{helper_base: helper_base}}, helper_prefix)
       when is_binary(helper_base) do
    String.starts_with?(helper_base <> "_path", helper_prefix) or
      String.starts_with?(helper_base <> "_url", helper_prefix)
  end

  defp route_helper_match?(_fact, _helper_prefix), do: false

  defp find_schema_field(facts, field_prefix) do
    Enum.find(
      facts,
      &(&1.kind == :schema_field and String.starts_with?(&1.data.name, field_prefix))
    )
  end

  defp find_assign(facts, assign_prefix) do
    Enum.find(facts, &(&1.kind == :assign and String.starts_with?(&1.data.name, assign_prefix)))
  end

  defp find_assign_schema_property(facts, prefix) do
    with {:ok, assign, path, field_prefix} <- AssignAccess.field_access(prefix),
         {:ok, base_schema_id} <- SchemaFacts.schema_id_for_assign(assign, facts),
         {:ok, schema_id} <- schema_id_for_path(base_schema_id, path, facts) do
      SchemaFacts.schema_property(schema_id, field_prefix, facts)
    else
      _not_assign_field -> nil
    end
  end

  defp schema_id_for_path(schema_id, [], _facts), do: {:ok, schema_id}

  defp schema_id_for_path(schema_id, path, facts) do
    SchemaFacts.schema_id_for_association_path(schema_id, path, facts)
  end

  defp find_live_event(facts, event_prefix) do
    Enum.find(
      facts,
      &(&1.kind == :live_event and String.starts_with?(&1.data.event, event_prefix))
    )
  end

  defp route_path_prefix("~p\"" <> path), do: path
  defp route_path_prefix("~p'" <> path), do: path
  defp route_helper_prefix("Routes." <> helper), do: helper

  defp form_field_prefix("@form[:" <> field), do: field
end
