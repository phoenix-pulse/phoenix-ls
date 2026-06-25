defmodule PhoenixLS.Introspection.Controller.Plugs do
  @moduledoc """
  Extracts conservative controller plug assign facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Controller.{PlugAssign, Renders}
  alias PhoenixLS.Introspection.Source

  @spec facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    plug_names = plug_names(expressions)
    function_bodies = function_bodies(expressions)

    plug_names
    |> Enum.flat_map(fn {plug, _plug_range} ->
      function_bodies
      |> Map.get(plug, [])
      |> Enum.flat_map(&Renders.assign_entries/1)
      |> Enum.map(fn %{range: range, name: name} ->
        Fact.new!(
          kind: :controller_plug_assign,
          id:
            "#{module}:plug_assign:#{plug}:#{name}:#{range.start.line}:#{range.start.character}",
          uri: uri,
          range: range,
          provenance: provenance,
          data: %PlugAssign{
            module: module,
            plug: plug,
            name: name,
            confidence: :medium
          }
        )
      end)
    end)
  end

  defp plug_names(expressions) do
    expressions
    |> Enum.flat_map(fn
      {:plug, meta, [name | _rest]} when is_atom(name) ->
        [{Atom.to_string(name), Source.source_range(meta)}]

      _expression ->
        []
    end)
  end

  defp function_bodies(expressions) do
    expressions
    |> Enum.reduce(%{}, fn
      {visibility, _meta, [head, body_ast]}, acc when visibility in [:def, :defp] ->
        case function_name(head) do
          {:ok, name} -> Map.update(acc, name, [body(body_ast)], &[body(body_ast) | &1])
          :error -> acc
        end

      _expression, acc ->
        acc
    end)
  end

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)

  defp function_name({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {:ok, Atom.to_string(name)}

  defp function_name(_head), do: :error

  defp body(do: body), do: body
  defp body(keyword) when is_list(keyword), do: Keyword.get(keyword, :do)
  defp body(body), do: body
end
