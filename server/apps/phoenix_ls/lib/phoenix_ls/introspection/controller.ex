defmodule PhoenixLS.Introspection.Controller do
  @moduledoc """
  Source-only extraction helpers for Phoenix controller facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Controller.{Actions, Plugs, Renders}
  alias PhoenixLS.Introspection.Source

  defmodule Controller do
    @moduledoc """
    Typed Phoenix controller module fact payload.
    """

    @enforce_keys [:module]
    defstruct [:module]
  end

  defmodule Action do
    @moduledoc """
    Typed Phoenix controller action fact payload.
    """

    @enforce_keys [:module, :action, :arity]
    defstruct [:module, :action, :arity]
  end

  defmodule Render do
    @moduledoc """
    Typed Phoenix controller render fact payload.
    """

    @enforce_keys [:module, :action, :template, :format, :candidate_uris, :assigns, :confidence]
    defstruct [:module, :action, :template, :format, :candidate_uris, :assigns, :confidence]
  end

  defmodule Assign do
    @moduledoc """
    Typed Phoenix controller assign fact payload.
    """

    @enforce_keys [:module, :action, :name, :source, :confidence]
    defstruct [:module, :action, :name, :source, :confidence, :schema_source]
  end

  defmodule Layout do
    @moduledoc """
    Typed Phoenix controller layout fact payload.
    """

    @enforce_keys [:module, :action, :layout, :source, :confidence]
    defstruct [:module, :action, :layout, :source, :confidence]
  end

  defmodule PlugAssign do
    @moduledoc """
    Typed Phoenix controller plug-propagated assign fact payload.
    """

    @enforce_keys [:module, :plug, :name, :confidence]
    defstruct [:module, :plug, :name, :confidence]
  end

  @spec controller_module?(term()) :: boolean()
  def controller_module?(body_ast) do
    case body_ast |> Source.top_level_expressions() |> controller_range() do
      {:ok, _range} -> true
      :error -> false
    end
  end

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    expressions = Source.top_level_expressions(body_ast)

    case controller_range(expressions) do
      {:ok, range} ->
        actions = Actions.entries(expressions)

        [
          controller_fact(module, range, uri, provenance)
          | Actions.facts(module, actions, uri, provenance)
        ] ++
          Renders.facts(module, actions, uri, provenance) ++
          Plugs.facts(module, expressions, uri, provenance)

      :error ->
        []
    end
  end

  defp controller_range(expressions) do
    expressions
    |> Enum.find_value(fn
      {:use, meta, [{:__aliases__, _alias_meta, [:Phoenix, :Controller]}]} ->
        {:ok, Source.source_range(meta)}

      {:use, meta, [_module_ast, :controller]} ->
        {:ok, Source.source_range(meta)}

      _expression ->
        nil
    end)
    |> case do
      nil -> :error
      result -> result
    end
  end

  defp controller_fact(module, range, uri, provenance) do
    Fact.new!(
      kind: :controller,
      id: module,
      uri: uri,
      range: range,
      provenance: provenance,
      data: %Controller{module: module}
    )
  end
end
