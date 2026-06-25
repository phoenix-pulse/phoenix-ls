defmodule PhoenixLS.Introspection.LiveView.Lifecycle do
  @moduledoc """
  Source-only extraction of LiveView lifecycle, async, hook, and message facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.LiveView.Function
  alias PhoenixLS.Introspection.LiveView.TemporaryAssigns
  alias PhoenixLS.Introspection.Source

  defmodule Async do
    @moduledoc """
    Typed LiveView async fact payload.
    """

    @enforce_keys [:module, :name, :source, :handler, :confidence]
    defstruct [:module, :name, :source, :handler, :confidence]
  end

  defmodule TemporaryAssign do
    @moduledoc """
    Typed LiveView temporary assign fact payload.
    """

    @enforce_keys [:module, :name, :default, :source]
    defstruct [:module, :name, :default, :source]
  end

  defmodule Hook do
    @moduledoc """
    Typed LiveView attach_hook fact payload.
    """

    @enforce_keys [:module, :name, :stage]
    defstruct [:module, :name, :stage]
  end

  defmodule Message do
    @moduledoc """
    Typed LiveView server message handler fact payload.
    """

    @enforce_keys [:module, :name, :pattern, :handler]
    defstruct [:module, :name, :pattern, :handler]
  end

  @callbacks %{
    mount: 3,
    handle_params: 3,
    handle_async: 3,
    handle_call: 3,
    handle_cast: 2,
    handle_info: 2,
    render: 1
  }

  @spec facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    function_facts(module, expressions, uri, provenance) ++
      async_facts(module, expressions, uri, provenance) ++
      temporary_assign_facts(module, expressions, uri, provenance) ++
      hook_facts(module, expressions, uri, provenance) ++
      message_facts(module, expressions, uri, provenance)
  end

  @spec function_facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def function_facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    expressions
    |> Enum.flat_map(fn
      {:def, meta, [head, _body]} ->
        case live_view_function(head) do
          {:ok, name, arity, type} ->
            [
              Fact.new!(
                kind: :live_view_function,
                id: "#{module}:live_view_function:#{name}/#{arity}",
                uri: uri,
                range: Source.source_range(meta),
                provenance: provenance,
                data: %Function{
                  module: module,
                  name: name,
                  type: type,
                  arity: arity
                }
              )
            ]

          :error ->
            []
        end

      _expression ->
        []
    end)
  end

  @spec temporary_assign_entries([term()]) :: [
          %{range: GenLSP.Structures.Range.t(), name: String.t(), default: String.t()}
        ]
  def temporary_assign_entries(expressions) when is_list(expressions) do
    TemporaryAssigns.entries(expressions)
  end

  defp async_facts(module, expressions, uri, provenance) do
    async_call_facts(module, expressions, uri, provenance) ++
      async_handler_facts(module, expressions, uri, provenance)
  end

  defp async_call_facts(module, expressions, uri, provenance) do
    expressions
    |> nodes()
    |> Enum.flat_map(fn
      {source, meta, args} when source in [:assign_async, :start_async] and is_list(args) ->
        args
        |> Enum.take(2)
        |> Enum.flat_map(&static_names/1)
        |> Enum.map(
          &async_fact(module, &1, source, nil, Source.source_range(meta), uri, provenance)
        )

      _node ->
        []
    end)
  end

  defp async_handler_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(fn
      {:def, meta, [head, _body]} ->
        with {:ok, args} <- callback_args(head, :handle_async, 3) do
          args
          |> List.first()
          |> static_names()
          |> Enum.map(
            &async_fact(
              module,
              &1,
              :handle_async,
              "handle_async/3",
              Source.source_range(meta),
              uri,
              provenance
            )
          )
        else
          :error -> []
        end

      _expression ->
        []
    end)
  end

  defp async_fact(module, name, source, handler, range, uri, provenance) do
    Fact.new!(
      kind: :live_async,
      id: "#{module}:async:#{source}:#{name}",
      uri: uri,
      range: range,
      provenance: provenance,
      data: %Async{
        module: module,
        name: name,
        source: source,
        handler: handler,
        confidence: :exact
      }
    )
  end

  defp temporary_assign_facts(module, expressions, uri, provenance) do
    expressions
    |> temporary_assign_entries()
    |> Enum.map(fn %{range: range, name: name, default: default} ->
      Fact.new!(
        kind: :live_temporary_assign,
        id: "#{module}:temporary_assign:#{name}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %TemporaryAssign{
          module: module,
          name: name,
          default: default,
          source: :temporary_assigns
        }
      )
    end)
  end

  defp hook_facts(module, expressions, uri, provenance) do
    expressions
    |> nodes()
    |> Enum.flat_map(fn
      {:attach_hook, meta, args} when is_list(args) ->
        case hook_name_and_stage(args) do
          {:ok, name, stage} ->
            [
              Fact.new!(
                kind: :live_lifecycle_hook,
                id: "#{module}:hook:#{stage}:#{name}",
                uri: uri,
                range: Source.source_range(meta),
                provenance: provenance,
                data: %Hook{module: module, name: name, stage: stage}
              )
            ]

          :error ->
            []
        end

      _node ->
        []
    end)
  end

  defp message_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(fn
      {:def, meta, [head, _body]} ->
        with {:ok, [message_ast, _socket]} <- callback_args(head, :handle_info, 2),
             {:ok, name, pattern} <- message_pattern(message_ast) do
          [
            Fact.new!(
              kind: :live_message,
              id: "#{module}:message:#{name}:#{meta[:line] || 0}",
              uri: uri,
              range: Source.source_range(meta),
              provenance: provenance,
              data: %Message{
                module: module,
                name: name,
                pattern: pattern,
                handler: "handle_info/2"
              }
            )
          ]
        else
          :error -> []
        end

      _expression ->
        []
    end)
  end

  defp live_view_function({:when, _meta, [head | _guards]}), do: live_view_function(head)

  defp live_view_function({name, _meta, args}) when is_atom(name) and is_list(args) do
    case Map.fetch(@callbacks, name) do
      {:ok, arity} -> callback(name, args, arity)
      :error -> :error
    end
  end

  defp live_view_function(_head), do: :error

  defp callback(name, args, arity) when length(args) == arity do
    {:ok, Atom.to_string(name), arity, name}
  end

  defp callback(_name, _args, _arity), do: :error

  defp callback_args({:when, _meta, [head | _guards]}, name, arity) do
    callback_args(head, name, arity)
  end

  defp callback_args({name, _meta, args}, name, arity)
       when is_list(args) and length(args) == arity do
    {:ok, args}
  end

  defp callback_args(_head, _name, _arity), do: :error

  defp hook_name_and_stage([_socket, name_ast, stage_ast, _fun | _rest]) do
    static_hook(name_ast, stage_ast)
  end

  defp hook_name_and_stage([name_ast, stage_ast, _fun | _rest]) do
    static_hook(name_ast, stage_ast)
  end

  defp hook_name_and_stage(_args), do: :error

  defp static_hook(name_ast, stage) when is_atom(stage) do
    case static_names(name_ast) do
      [name] -> {:ok, name, stage}
      _not_static -> :error
    end
  end

  defp static_hook(_name_ast, _stage), do: :error

  defp message_pattern(message) when is_atom(message) do
    {:ok, Atom.to_string(message), Macro.to_string(message)}
  end

  defp message_pattern(message) when is_binary(message) do
    {:ok, message, inspect(message)}
  end

  defp message_pattern({head, _rest} = message) when is_atom(head) or is_binary(head) do
    {:ok, message_name(head), Macro.to_string(message)}
  end

  defp message_pattern({:{}, _meta, [head | _rest]} = message)
       when is_atom(head) or is_binary(head) do
    {:ok, message_name(head), Macro.to_string(message)}
  end

  defp message_pattern(_message), do: :error

  defp message_name(name) when is_atom(name), do: Atom.to_string(name)
  defp message_name(name) when is_binary(name), do: name

  defp static_names(name) when is_atom(name), do: [Atom.to_string(name)]

  defp static_names(names) when is_list(names) do
    Enum.flat_map(names, &static_names/1)
  end

  defp static_names(_name), do: []

  defp nodes(expressions) do
    {_ast, nodes} =
      Macro.prewalk(expressions, [], fn node, acc ->
        {node, [node | acc]}
      end)

    Enum.reverse(nodes)
  end
end
