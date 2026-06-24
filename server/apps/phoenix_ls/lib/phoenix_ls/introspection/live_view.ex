defmodule PhoenixLS.Introspection.LiveView do
  @moduledoc """
  Source-only extraction helpers for LiveView facts.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    expressions = top_level_expressions(body_ast)

    case live_view_range(expressions) do
      {:ok, range} ->
        [
          live_view_fact(module, range, uri, provenance)
          | event_facts(module, expressions, uri, provenance)
        ]

      :error ->
        []
    end
  end

  defp live_view_range(expressions) do
    expressions
    |> Enum.find_value(fn
      {:use, meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}]} ->
        {:ok, source_range(meta)}

      {:use, meta, [_module_ast, :live_view]} ->
        {:ok, source_range(meta)}

      _expression ->
        nil
    end)
    |> case do
      nil -> :error
      result -> result
    end
  end

  defp live_view_fact(module, range, uri, provenance) do
    Fact.new!(
      kind: :live_view,
      id: module,
      uri: uri,
      range: range,
      provenance: provenance,
      data: %{module: module}
    )
  end

  defp event_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(fn
      {:def, meta, [{:handle_event, _head_meta, [event, _params, _socket]}, _body]}
      when is_binary(event) ->
        [
          Fact.new!(
            kind: :live_event,
            id: "#{module}:event:#{event}",
            uri: uri,
            range: source_range(meta),
            provenance: provenance,
            data: %{
              module: module,
              event: event
            }
          )
        ]

      _expression ->
        []
    end)
  end

  defp top_level_expressions({:__block__, _meta, expressions}), do: expressions
  defp top_level_expressions(nil), do: []
  defp top_level_expressions(expression), do: [expression]

  defp source_range(meta) do
    %Range{
      start: position(meta),
      end: position(end_meta(meta))
    }
  end

  defp end_meta(meta) do
    Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end) || meta
  end

  defp position(meta) do
    %Position{
      line: meta |> Keyword.get(:line, 1) |> zero_based(),
      character: meta |> Keyword.get(:column, 1) |> zero_based()
    }
  end

  defp zero_based(value) when is_integer(value) and value > 0, do: value - 1
  defp zero_based(_value), do: 0
end
