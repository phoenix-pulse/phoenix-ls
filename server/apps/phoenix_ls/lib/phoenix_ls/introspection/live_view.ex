defmodule PhoenixLS.Introspection.LiveView do
  @moduledoc """
  Source-only extraction helpers for LiveView facts.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  defmodule LiveView do
    @moduledoc """
    Typed LiveView module fact payload.
    """

    @enforce_keys [:module]
    defstruct [:module]
  end

  defmodule Event do
    @moduledoc """
    Typed LiveView event fact payload.
    """

    @enforce_keys [:module, :event]
    defstruct [:module, :event]
  end

  defmodule Assign do
    @moduledoc """
    Typed LiveView assign fact payload.
    """

    @enforce_keys [:module, :name]
    defstruct [:module, :name]
  end

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    expressions = top_level_expressions(body_ast)

    case live_view_range(expressions) do
      {:ok, range} ->
        [
          live_view_fact(module, range, uri, provenance)
          | detail_facts(module, expressions, uri, provenance)
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
      data: %LiveView{module: module}
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
            data: %Event{
              module: module,
              event: event
            }
          )
        ]

      _expression ->
        []
    end)
  end

  defp detail_facts(module, expressions, uri, provenance) do
    event_facts(module, expressions, uri, provenance) ++
      assign_facts(module, expressions, uri, provenance)
  end

  defp assign_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(&assign_calls/1)
    |> Enum.uniq_by(fn {_meta, name} -> name end)
    |> Enum.map(fn {meta, name} ->
      Fact.new!(
        kind: :assign,
        id: "#{module}:assign:#{name}",
        uri: uri,
        range: source_range(meta),
        provenance: provenance,
        data: %Assign{
          module: module,
          name: name
        }
      )
    end)
  end

  defp assign_calls({:assign, meta, [_socket, name, _value]}) when is_atom(name) do
    [{meta, Atom.to_string(name)}]
  end

  defp assign_calls(list) when is_list(list) do
    Enum.flat_map(list, &assign_calls/1)
  end

  defp assign_calls(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&assign_calls/1)
  end

  defp assign_calls(_node), do: []

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
