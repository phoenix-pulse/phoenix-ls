defmodule PhoenixLS.Introspection.Router do
  @moduledoc """
  Source-only extraction helpers for Phoenix router facts.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  defmodule Route do
    @moduledoc """
    Typed route fact payload.
    """

    @enforce_keys [:router, :verb, :path, :plug, :scope_path]
    defstruct [:router, :verb, :path, :plug, :action, :scope_path, :scope_module]
  end

  @route_macros [:connect, :delete, :get, :head, :live, :options, :patch, :post, :put, :trace]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> top_level_expressions()
    |> Enum.flat_map(&collect_expression(&1, module, uri, provenance, nil, ""))
  end

  defp collect_expression(
         {:scope, _meta, args},
         router,
         uri,
         provenance,
         _scope_module,
         scope_path
       ) do
    case scope_context(args, scope_path) do
      {:ok, next_scope_module, next_scope_path, block} ->
        block
        |> top_level_expressions()
        |> Enum.flat_map(
          &collect_expression(&1, router, uri, provenance, next_scope_module, next_scope_path)
        )

      :error ->
        []
    end
  end

  defp collect_expression({verb, meta, args}, router, uri, provenance, scope_module, scope_path)
       when verb in @route_macros do
    case route_fact(verb, meta, args, router, uri, provenance, scope_module, scope_path) do
      {:ok, fact} -> [fact]
      :error -> []
    end
  end

  defp collect_expression(_expression, _router, _uri, _provenance, _scope_module, _scope_path),
    do: []

  defp scope_context([path, [do: block]], current_path) when is_binary(path) do
    {:ok, nil, join_paths(current_path, path), block}
  end

  defp scope_context([path, module_ast, [do: block]], current_path) when is_binary(path) do
    with {:ok, module} <- alias_to_string(module_ast) do
      {:ok, module, join_paths(current_path, path), block}
    end
  end

  defp scope_context(_args, _current_path), do: :error

  defp route_fact(
         verb,
         meta,
         [path, plug_ast | rest],
         router,
         uri,
         provenance,
         scope_module,
         scope_path
       )
       when is_binary(path) do
    with {:ok, plug} <- scoped_alias(plug_ast, scope_module),
         {:ok, action} <- route_action(rest) do
      full_path = join_paths(scope_path, path)

      {:ok,
       Fact.new!(
         kind: :route,
         id: route_id(router, verb, full_path, plug, action),
         uri: uri,
         range: source_range(meta),
         provenance: provenance,
         data: %Route{
           router: router,
           verb: verb,
           path: full_path,
           plug: plug,
           action: action,
           scope_path: scope_path,
           scope_module: scope_module
         }
       )}
    end
  end

  defp route_fact(_verb, _meta, _args, _router, _uri, _provenance, _scope_module, _scope_path) do
    :error
  end

  defp route_action([action | _rest]) when is_atom(action), do: {:ok, action}
  defp route_action([]), do: {:ok, nil}
  defp route_action(_rest), do: :error

  defp route_id(router, verb, path, plug, nil), do: "#{router}:#{verb}:#{path}:#{plug}"

  defp route_id(router, verb, path, plug, action),
    do: "#{router}:#{verb}:#{path}:#{plug}:#{action}"

  defp scoped_alias(ast, nil), do: alias_to_string(ast)

  defp scoped_alias(ast, scope_module) do
    with {:ok, module} <- alias_to_string(ast) do
      if String.starts_with?(module, scope_module <> ".") or module == scope_module do
        {:ok, module}
      else
        {:ok, scope_module <> "." <> module}
      end
    end
  end

  defp alias_to_string({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1) do
      {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
    else
      :error
    end
  end

  defp alias_to_string(atom) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  defp alias_to_string(_ast), do: :error

  defp join_paths("", path), do: normalize_path(path)
  defp join_paths("/", path), do: normalize_path(path)

  defp join_paths(scope_path, path) do
    scope = scope_path |> normalize_path() |> String.trim_trailing("/")
    route = path |> normalize_path() |> String.trim_leading("/")

    normalize_path(scope <> "/" <> route)
  end

  defp normalize_path(""), do: "/"
  defp normalize_path("/" <> _rest = path), do: path
  defp normalize_path(path), do: "/" <> path

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
