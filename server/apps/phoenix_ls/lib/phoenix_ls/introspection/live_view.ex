defmodule PhoenixLS.Introspection.LiveView do
  @moduledoc """
  Source-only extraction helpers for LiveView facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source
  alias PhoenixLS.Introspection.LiveView.Assigns
  alias PhoenixLS.Introspection.LiveView.Lifecycle
  alias PhoenixLS.Introspection.LiveView.Navigation
  alias PhoenixLS.Introspection.LiveView.Uploads

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

    @enforce_keys [:module, :event, :type, :handler, :arity]
    defstruct [:module, :event, :type, :handler, :arity]
  end

  defmodule Assign do
    @moduledoc """
    Typed LiveView assign fact payload.
    """

    @enforce_keys [:module, :name, :source]
    defstruct [:module, :name, :source]
  end

  defmodule Function do
    @moduledoc """
    Typed LiveView callback function fact payload.
    """

    @enforce_keys [:module, :name, :type, :arity]
    defstruct [:module, :name, :type, :arity]
  end

  @spec live_view_module?(term()) :: boolean()
  def live_view_module?(body_ast) do
    body_ast
    |> Source.top_level_expressions()
    |> live_view_range()
    |> case do
      {:ok, _range} -> true
      :error -> false
    end
  end

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    expressions = Source.top_level_expressions(body_ast)

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
        {:ok, Source.source_range(meta)}

      {:use, meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveComponent]}]} ->
        {:ok, Source.source_range(meta)}

      {:use, meta, [_module_ast, :live_view]} ->
        {:ok, Source.source_range(meta)}

      {:use, meta, [_module_ast, :live_component]} ->
        {:ok, Source.source_range(meta)}

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
      {:def, meta, [head, _body]} ->
        case live_event(head) do
          {:ok, event, type, arity} ->
            [
              Fact.new!(
                kind: :live_event,
                id: "#{module}:event:#{event}",
                uri: uri,
                range: Source.source_range(meta),
                provenance: provenance,
                data: %Event{
                  module: module,
                  event: event,
                  type: type,
                  handler: "#{type}/#{arity}",
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

  defp detail_facts(module, expressions, uri, provenance) do
    Lifecycle.facts(module, expressions, uri, provenance) ++
      event_facts(module, expressions, uri, provenance) ++
      Assigns.facts(module, expressions, uri, provenance) ++
      Navigation.facts(module, expressions, uri, provenance) ++
      Uploads.facts(module, expressions, uri, provenance)
  end

  defp live_event({:when, _meta, [head | _guards]}), do: live_event(head)

  defp live_event({:handle_event, _meta, [event, _params, _socket]}) when is_binary(event),
    do: {:ok, event, :handle_event, 3}

  defp live_event(_head), do: :error
end
