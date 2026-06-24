defmodule PhoenixLS.Features.PhoenixFactLookup do
  @moduledoc """
  Resolves cursor contexts to indexed Phoenix facts.
  """

  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec cursor_fact(CursorContext.t(), [Fact.t()]) :: Fact.t() | nil
  def cursor_fact(%CursorContext{kind: :tag_name, prefix: "." <> component_name}, facts) do
    find_component(facts, component_name)
  end

  def cursor_fact(
        %CursorContext{kind: :attribute_name, tag: "." <> component_name, prefix: prefix},
        facts
      ) do
    find_component_attr(facts, component_name, prefix)
  end

  def cursor_fact(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    cond do
      String.starts_with?(prefix, "~p\"") or String.starts_with?(prefix, "~p'") ->
        find_route(facts, route_path_prefix(prefix))

      String.starts_with?(prefix, "@form[:") ->
        find_schema_field(facts, form_field_prefix(prefix))

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

  defp find_component(facts, name) do
    Enum.find(facts, &(&1.kind == :component and &1.data.name == name))
  end

  defp find_component_attr(facts, component_name, prefix) do
    Enum.find(
      facts,
      &(&1.kind == :component_attr and &1.data.component_name == component_name and
          String.starts_with?(&1.data.name, prefix))
    )
  end

  defp find_route(facts, path_prefix) do
    Enum.find(facts, &(&1.kind == :route and String.starts_with?(&1.data.path, path_prefix)))
  end

  defp find_schema_field(facts, field_prefix) do
    Enum.find(
      facts,
      &(&1.kind == :schema_field and String.starts_with?(&1.data.name, field_prefix))
    )
  end

  defp find_assign(facts, assign_prefix) do
    Enum.find(facts, &(&1.kind == :assign and String.starts_with?(&1.data.name, assign_prefix)))
  end

  defp find_live_event(facts, event_prefix) do
    Enum.find(
      facts,
      &(&1.kind == :live_event and String.starts_with?(&1.data.event, event_prefix))
    )
  end

  defp route_path_prefix("~p\"" <> path), do: path
  defp route_path_prefix("~p'" <> path), do: path

  defp form_field_prefix("@form[:" <> field), do: field
end
