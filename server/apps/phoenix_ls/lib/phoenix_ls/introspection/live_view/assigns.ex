defmodule PhoenixLS.Introspection.LiveView.Assigns do
  @moduledoc """
  Source-only extraction of LiveView assign facts from Elixir AST.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.LiveView.Assign
  alias PhoenixLS.Introspection.LiveView.Lifecycle
  alias PhoenixLS.Introspection.Source

  @type assign_source ::
          :assign
          | :assign_new
          | :update
          | :stream
          | :stream_insert
          | :assign_async
          | :temporary_assigns

  @spec facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    (Enum.flat_map(expressions, &assign_calls/1) ++ temporary_assign_calls(expressions))
    |> Enum.uniq_by(fn {_range, name, _source} -> name end)
    |> Enum.map(fn {range, name, source} ->
      Fact.new!(
        kind: :assign,
        id: "#{module}:assign:#{name}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Assign{
          module: module,
          name: name,
          source: source
        }
      )
    end)
  end

  defp temporary_assign_calls(expressions) do
    expressions
    |> Lifecycle.temporary_assign_entries()
    |> Enum.map(fn %{range: range, name: name} -> {range, name, :temporary_assigns} end)
  end

  defp assign_calls({:assign, meta, args}) when is_list(args) do
    assign_call(meta, args)
  end

  defp assign_calls({:assign_new, meta, args}) when is_list(args) do
    named_call(:assign_new, meta, args)
  end

  defp assign_calls({:update, meta, args}) when is_list(args) do
    named_call(:update, meta, args)
  end

  defp assign_calls({:stream, meta, args}) when is_list(args) do
    named_call(:stream, meta, args)
  end

  defp assign_calls({:stream_insert, meta, args}) when is_list(args) do
    named_call(:stream_insert, meta, args)
  end

  defp assign_calls({:assign_async, meta, args}) when is_list(args) do
    named_call(:assign_async, meta, args)
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

  defp assign_call(meta, [_socket, keyword]) when is_list(keyword) do
    keyword_assigns(:assign, meta, keyword)
  end

  defp assign_call(meta, [keyword]) when is_list(keyword) do
    keyword_assigns(:assign, meta, keyword)
  end

  defp assign_call(meta, [_socket, name_ast, _value]) do
    static_names(:assign, meta, name_ast)
  end

  defp assign_call(meta, [name_ast, _value]) do
    static_names(:assign, meta, name_ast)
  end

  defp assign_call(_meta, _args), do: []

  defp named_call(source, meta, args) do
    args
    |> Enum.take(2)
    |> Enum.find_value([], fn name_ast ->
      case static_names(source, meta, name_ast) do
        [] -> nil
        names -> names
      end
    end)
  end

  defp keyword_assigns(source, meta, keyword) do
    if Keyword.keyword?(keyword) do
      keyword
      |> Enum.flat_map(fn
        {name, _value} when is_atom(name) ->
          [{source_range(name, meta), Atom.to_string(name), source}]

        _entry ->
          []
      end)
    else
      []
    end
  end

  defp static_names(source, meta, name) when is_atom(name) do
    [{source_range(name, meta), Atom.to_string(name), source}]
  end

  defp static_names(source, meta, names) when is_list(names) do
    names
    |> Enum.flat_map(fn name -> static_names(source, meta, name) end)
  end

  defp static_names(_source, _meta, _name), do: []

  defp source_range(_name, call_meta) do
    Source.source_range(call_meta)
  end
end
