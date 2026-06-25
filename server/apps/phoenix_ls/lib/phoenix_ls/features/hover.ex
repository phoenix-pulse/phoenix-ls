defmodule PhoenixLS.Features.Hover do
  @moduledoc """
  Hover content for Phoenix source facts.
  """

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.{Hover, MarkupContent}
  alias PhoenixLS.Features.{PhoenixFactLookup, SourceReferenceLookup}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.URI, as: SupportURI

  @spec hover(CursorContext.t(), [Fact.t()]) :: Hover.t() | nil
  def hover(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> hover_for_fact()
  end

  @spec hover(String.t(), %{line: non_neg_integer(), character: non_neg_integer()}, [Fact.t()]) ::
          Hover.t() | nil
  def hover(uri, position, facts) when is_binary(uri) and is_list(facts) do
    uri
    |> SourceReferenceLookup.target_at(position, facts)
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

  defp markdown(%Fact{kind: :component_slot} = fact) do
    [
      code("slot :#{fact.data.name}"),
      option_lines(fact.data.options),
      fact.data.component
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :component_slot_attr} = fact) do
    [
      code("slot attr :#{fact.data.name}, #{inspect(fact.data.type)}"),
      "slot :#{fact.data.slot}",
      option_lines(fact.data.options),
      fact.data.component
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

  defp markdown(%Fact{kind: :template} = fact) do
    [
      code("template #{template_name(fact.uri)}"),
      "format #{inspect(fact.data.format)}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :schema} = fact) do
    [
      code(schema_declaration(fact.data)),
      "module #{fact.data.module}",
      primary_key_line(fact.data.primary_key),
      "foreign key type #{inspect(fact.data.foreign_key_type)}"
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

  defp markdown(%Fact{kind: :schema_association} = fact) do
    [
      code("#{fact.data.association} :#{fact.data.name}, #{fact.data.related}"),
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

  defp template_name(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> Path.basename(path)
      {:error, _reason} -> uri
    end
  end

  defp schema_declaration(%{source: nil}), do: "embedded_schema"
  defp schema_declaration(%{source: source}), do: ~s(schema "#{source}")

  defp primary_key_line(false), do: "primary key false"
  defp primary_key_line(%{name: name, type: type}), do: "primary key :#{name}, #{inspect(type)}"

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
