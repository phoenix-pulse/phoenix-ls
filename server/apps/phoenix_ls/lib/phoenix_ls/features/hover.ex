defmodule PhoenixLS.Features.Hover do
  @moduledoc """
  Hover content for Phoenix source facts.
  """

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.{Hover, MarkupContent}
  alias PhoenixLS.Features.PhoenixFactLookup
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec hover(CursorContext.t(), [Fact.t()]) :: Hover.t() | nil
  def hover(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> hover_for_fact()
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
