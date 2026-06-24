defmodule PhoenixLS.Features.Hover do
  @moduledoc """
  Hover content for Phoenix source facts.
  """

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.{Hover, MarkupContent}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec hover(CursorContext.t(), [Fact.t()]) :: Hover.t() | nil
  def hover(%CursorContext{kind: :tag_name, prefix: "." <> component_name}, facts) do
    facts
    |> find_component(component_name)
    |> hover_for_fact()
  end

  def hover(
        %CursorContext{kind: :attribute_name, tag: "." <> component_name, prefix: prefix},
        facts
      ) do
    facts
    |> find_component_attr(component_name, prefix)
    |> hover_for_fact()
  end

  def hover(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    cond do
      String.starts_with?(prefix, "~p\"") or String.starts_with?(prefix, "~p'") ->
        facts
        |> find_route(route_path_prefix(prefix))
        |> hover_for_fact()

      String.starts_with?(prefix, "@form[:") ->
        facts
        |> find_schema_field(form_field_prefix(prefix))
        |> hover_for_fact()

      String.starts_with?(prefix, "@") ->
        facts
        |> find_assign(String.trim_leading(prefix, "@"))
        |> hover_for_fact()

      true ->
        nil
    end
  end

  def hover(
        %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
        facts
      ) do
    facts
    |> find_live_event(prefix)
    |> hover_for_fact()
  end

  def hover(_context, _facts), do: nil

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

  defp hover_for_fact(nil), do: nil

  defp hover_for_fact(%Fact{} = fact) do
    %Hover{
      contents: %MarkupContent{
        kind: MarkupKind.markdown(),
        value: markdown(fact)
      }
    }
  end

  defp markdown(%Fact{kind: :component} = fact) do
    [
      code("component #{fact.id}"),
      Map.get(fact.data, :doc)
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :component_attr} = fact) do
    [
      code("attr :#{fact.data.name}, #{inspect(fact.data.type)}"),
      option_lines(fact.data.options),
      Keyword.get(fact.data.options || [], :doc)
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :route} = fact) do
    route =
      case fact.data.action do
        nil -> "#{fact.data.verb} \"#{fact.data.path}\", #{fact.data.plug}"
        action -> "#{fact.data.verb} \"#{fact.data.path}\", #{fact.data.plug}, :#{action}"
      end

    [
      code(route),
      "router #{fact.data.router}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :schema_field} = fact) do
    [
      code("field :#{fact.data.name}, #{inspect(fact.data.type)}"),
      "schema #{fact.data.module}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :assign} = fact) do
    [
      code("assign @#{fact.data.name}"),
      fact.data.module
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :live_event} = fact) do
    [
      code("handle_event(\"#{fact.data.event}\", ...)"),
      fact.data.module
    ]
    |> compact_join()
  end

  defp markdown(_fact), do: ""

  defp route_path_prefix("~p\"" <> path), do: path
  defp route_path_prefix("~p'" <> path), do: path

  defp form_field_prefix("@form[:" <> field), do: field

  defp option_lines(options) do
    options
    |> List.wrap()
    |> Enum.reject(fn {key, _value} -> key == :doc end)
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> compact_join()
  end

  defp code(value) do
    "```elixir\n#{value}\n```"
  end

  defp compact_join(values) do
    values
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
