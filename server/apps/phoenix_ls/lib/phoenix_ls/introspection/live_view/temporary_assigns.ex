defmodule PhoenixLS.Introspection.LiveView.TemporaryAssigns do
  @moduledoc """
  Extracts LiveView temporary assign entries from already-parsed Elixir AST nodes.
  """

  alias PhoenixLS.Introspection.Source

  @spec entries([term()]) :: [
          %{range: GenLSP.Structures.Range.t(), name: String.t(), default: String.t()}
        ]
  def entries(expressions) when is_list(expressions) do
    expressions
    |> nodes()
    |> Enum.flat_map(&entries_from_node/1)
    |> Enum.uniq_by(& &1.name)
  end

  defp entries_from_node({:__block__, meta, expressions}) when is_list(expressions) do
    entries_from_options(expressions, Source.source_range(meta))
  end

  defp entries_from_node({call, meta, args}) when is_atom(call) and is_list(args) do
    entries_from_options(args, Source.source_range(meta))
  end

  defp entries_from_node(_node), do: []

  defp entries_from_options(args, range) do
    args
    |> Enum.flat_map(fn
      options when is_list(options) ->
        entries_from_keyword(options, range)

      _arg ->
        []
    end)
  end

  defp entries_from_keyword(options, range) do
    with true <- Keyword.keyword?(options),
         temporary_assigns when is_list(temporary_assigns) <-
           Keyword.get(options, :temporary_assigns),
         true <- Keyword.keyword?(temporary_assigns) do
      Enum.flat_map(temporary_assigns, fn
        {name, default} when is_atom(name) ->
          [%{range: range, name: Atom.to_string(name), default: Macro.to_string(default)}]

        _entry ->
          []
      end)
    else
      _not_temporary_assigns -> []
    end
  end

  defp nodes(expressions) do
    {_ast, nodes} =
      Macro.prewalk(expressions, [], fn node, acc ->
        {node, [node | acc]}
      end)

    Enum.reverse(nodes)
  end
end
