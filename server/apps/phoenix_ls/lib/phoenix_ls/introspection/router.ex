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

    @enforce_keys [
      :router,
      :verb,
      :path,
      :plug,
      :scope_path,
      :helper_base,
      :path_params,
      :pipelines
    ]
    defstruct [
      :router,
      :verb,
      :path,
      :plug,
      :action,
      :scope_path,
      :scope_module,
      :helper_base,
      :path_params,
      :pipelines,
      :live_session
    ]
  end

  @route_macros [:connect, :delete, :get, :head, :live, :options, :patch, :post, :put, :trace]
  @resource_actions [:index, :new, :edit, :show, :create, :update, :delete]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> top_level_expressions()
    |> collect_expressions(module, uri, provenance, nil, "", [], nil)
  end

  defp collect_expressions(
         expressions,
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       ) do
    expressions
    |> Enum.reduce({[], pipelines}, fn expression, {facts, current_pipelines} ->
      {new_facts, next_pipelines} =
        collect_expression(
          expression,
          router,
          uri,
          provenance,
          scope_module,
          scope_path,
          current_pipelines,
          live_session
        )

      {facts ++ new_facts, next_pipelines}
    end)
    |> elem(0)
  end

  defp collect_expression(
         {:scope, _meta, args},
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       ) do
    case scope_context(args, scope_path, scope_module) do
      {:ok, next_scope_module, next_scope_path, block} ->
        facts =
          block
          |> top_level_expressions()
          |> collect_expressions(
            router,
            uri,
            provenance,
            next_scope_module,
            next_scope_path,
            pipelines,
            live_session
          )

        {facts, pipelines}

      :error ->
        {[], pipelines}
    end
  end

  defp collect_expression(
         {:pipe_through, _meta, args},
         _router,
         _uri,
         _provenance,
         _scope_module,
         _scope_path,
         pipelines,
         _live_session
       ) do
    case pipe_through_pipelines(args) do
      {:ok, next_pipelines} -> {[], pipelines ++ next_pipelines}
      :error -> {[], pipelines}
    end
  end

  defp collect_expression(
         {:live_session, _meta, args},
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         _live_session
       ) do
    case live_session_context(args) do
      {:ok, next_live_session, block} ->
        facts =
          block
          |> top_level_expressions()
          |> collect_expressions(
            router,
            uri,
            provenance,
            scope_module,
            scope_path,
            pipelines,
            next_live_session
          )

        {facts, pipelines}

      :error ->
        {[], pipelines}
    end
  end

  defp collect_expression(
         {:resources, meta, args},
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       ) do
    {
      resource_facts(
        meta,
        args,
        router,
        uri,
        provenance,
        scope_module,
        scope_path,
        pipelines,
        live_session
      ),
      pipelines
    }
  end

  defp collect_expression(
         {:forward, meta, args},
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       ) do
    case route_fact(
           :forward,
           meta,
           args,
           router,
           uri,
           provenance,
           scope_module,
           scope_path,
           pipelines,
           live_session
         ) do
      {:ok, fact} -> {[fact], pipelines}
      :error -> {[], pipelines}
    end
  end

  defp collect_expression(
         {verb, meta, args},
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       )
       when verb in @route_macros do
    case route_fact(
           verb,
           meta,
           args,
           router,
           uri,
           provenance,
           scope_module,
           scope_path,
           pipelines,
           live_session
         ) do
      {:ok, fact} -> {[fact], pipelines}
      :error -> {[], pipelines}
    end
  end

  defp collect_expression(
         _expression,
         _router,
         _uri,
         _provenance,
         _scope_module,
         _scope_path,
         pipelines,
         _live_session
       ),
       do: {[], pipelines}

  defp live_session_context([name, [do: block]]) do
    {:ok, session_name(name), block}
  end

  defp live_session_context([name, opts, [do: block]]) when is_list(opts) do
    {:ok, session_name(name), block}
  end

  defp live_session_context(_args), do: :error

  defp session_name(name) when is_atom(name), do: Atom.to_string(name)
  defp session_name(name) when is_binary(name), do: name
  defp session_name(name), do: inspect(name)

  defp pipe_through_pipelines([pipeline_ast]) do
    case pipeline_names(pipeline_ast) do
      [] -> :error
      names -> {:ok, names}
    end
  end

  defp pipe_through_pipelines(_args), do: :error

  defp pipeline_names(pipelines) when is_list(pipelines) do
    pipelines
    |> Enum.map(&pipeline_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp pipeline_names(pipeline), do: pipeline_names([pipeline])

  defp pipeline_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp pipeline_name(_pipeline), do: nil

  defp scope_context([path, [do: block]], current_path, current_module) when is_binary(path) do
    {:ok, current_module, join_paths(current_path, path), block}
  end

  defp scope_context([path, module_ast, [do: block]], current_path, current_module)
       when is_binary(path) do
    with {:ok, module} <- scoped_alias(module_ast, current_module) do
      {:ok, module, join_paths(current_path, path), block}
    end
  end

  defp scope_context(_args, _current_path, _current_module), do: :error

  defp route_fact(
         verb,
         meta,
         [path, plug_ast | rest],
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       )
       when is_binary(path) do
    with {:ok, plug} <- scoped_alias(plug_ast, scope_module),
         {:ok, action} <- route_action(verb, rest) do
      full_path = join_paths(scope_path, path)

      {:ok,
       route_fact!(
         router,
         verb,
         full_path,
         plug,
         action,
         uri,
         meta,
         provenance,
         scope_path,
         scope_module,
         pipelines,
         live_session
       )}
    end
  end

  defp route_fact(
         _verb,
         _meta,
         _args,
         _router,
         _uri,
         _provenance,
         _scope_module,
         _scope_path,
         _pipelines,
         _live_session
       ) do
    :error
  end

  defp resource_facts(
         meta,
         [path, controller_ast | rest],
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         pipelines,
         live_session
       )
       when is_binary(path) do
    with {:ok, controller} <- scoped_alias(controller_ast, scope_module),
         {:ok, actions, param} <- resource_options(rest) do
      base_path = join_paths(scope_path, path)

      actions
      |> Enum.flat_map(&resource_route_specs(base_path, &1, param))
      |> Enum.map(fn {verb, route_path, action} ->
        route_fact!(
          router,
          verb,
          route_path,
          controller,
          action,
          uri,
          meta,
          provenance,
          scope_path,
          scope_module,
          pipelines,
          live_session
        )
      end)
    else
      :error -> []
    end
  end

  defp resource_facts(
         _meta,
         _args,
         _router,
         _uri,
         _provenance,
         _scope_module,
         _scope_path,
         _pipelines,
         _live_session
       ),
       do: []

  defp route_fact!(
         router,
         verb,
         full_path,
         plug,
         action,
         uri,
         meta,
         provenance,
         scope_path,
         scope_module,
         pipelines,
         live_session
       ) do
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
        scope_module: scope_module,
        helper_base: helper_base(full_path),
        path_params: path_params(full_path),
        pipelines: pipelines,
        live_session: live_session
      }
    )
  end

  defp resource_options([]), do: {:ok, @resource_actions, "id"}

  defp resource_options([opts | _rest]) when is_list(opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])
    param = resource_param(opts)

    actions =
      case only do
        actions when is_list(actions) -> actions
        nil -> @resource_actions
        _other -> []
      end

    {:ok,
     actions
     |> Enum.filter(&(&1 in @resource_actions))
     |> Enum.reject(&(&1 in except)), param}
  end

  defp resource_options(_rest), do: :error

  defp resource_param(opts) do
    case Keyword.get(opts, :param, "id") do
      param when is_binary(param) -> param
      param when is_atom(param) -> Atom.to_string(param)
      _other -> "id"
    end
  end

  defp resource_route_specs(base_path, :index, _param), do: [{:get, base_path, :index}]

  defp resource_route_specs(base_path, :new, _param),
    do: [{:get, join_paths(base_path, "new"), :new}]

  defp resource_route_specs(base_path, :edit, param),
    do: [{:get, join_paths(base_path, ":#{param}/edit"), :edit}]

  defp resource_route_specs(base_path, :show, param),
    do: [{:get, join_paths(base_path, ":#{param}"), :show}]

  defp resource_route_specs(base_path, :create, _param), do: [{:post, base_path, :create}]

  defp resource_route_specs(base_path, :update, param) do
    path = join_paths(base_path, ":#{param}")
    [{:patch, path, :update}, {:put, path, :update}]
  end

  defp resource_route_specs(base_path, :delete, param),
    do: [{:delete, join_paths(base_path, ":#{param}"), :delete}]

  defp route_action(:forward, _rest), do: {:ok, nil}
  defp route_action(_verb, [action | _rest]) when is_atom(action), do: {:ok, action}
  defp route_action(_verb, []), do: {:ok, nil}
  defp route_action(_verb, _rest), do: :error

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

  defp helper_base(path) do
    path
    |> path_segments()
    |> Enum.reject(&dynamic_path_segment?/1)
    |> Enum.map(&normalize_helper_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&singularize/1)
    |> case do
      [] -> "root"
      segments -> Enum.join(segments, "_")
    end
  end

  defp path_params(path) do
    path
    |> path_segments()
    |> Enum.filter(&dynamic_path_segment?/1)
    |> Enum.map(&dynamic_param_name/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp path_segments(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end

  defp dynamic_path_segment?(":" <> _name), do: true
  defp dynamic_path_segment?("*" <> _name), do: true
  defp dynamic_path_segment?(_segment), do: false

  defp dynamic_param_name(":" <> name), do: normalize_helper_segment(name)
  defp dynamic_param_name("*" <> name), do: normalize_helper_segment(name)

  defp normalize_helper_segment(segment) do
    segment
    |> String.graphemes()
    |> Enum.map(&helper_grapheme/1)
    |> Enum.reject(&is_nil/1)
    |> collapse_underscores()
    |> trim_underscores()
    |> Enum.join()
  end

  defp helper_grapheme(grapheme) do
    cond do
      grapheme >= "A" and grapheme <= "Z" -> String.downcase(grapheme)
      grapheme >= "a" and grapheme <= "z" -> grapheme
      grapheme >= "0" and grapheme <= "9" -> grapheme
      true -> "_"
    end
  end

  defp collapse_underscores(graphemes) do
    graphemes
    |> Enum.reduce([], fn
      "_", ["_" | _rest] = acc -> acc
      grapheme, acc -> [grapheme | acc]
    end)
    |> Enum.reverse()
  end

  defp trim_underscores(graphemes) do
    graphemes
    |> Enum.drop_while(&(&1 == "_"))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == "_"))
    |> Enum.reverse()
  end

  defp singularize(segment) do
    cond do
      String.ends_with?(segment, "ies") and String.length(segment) > 3 ->
        String.trim_trailing(segment, "ies") <> "y"

      String.ends_with?(segment, "ses") and String.length(segment) > 3 ->
        String.trim_trailing(segment, "es")

      (String.ends_with?(segment, "xes") or String.ends_with?(segment, "zes")) and
          String.length(segment) > 3 ->
        String.trim_trailing(segment, "es")

      String.ends_with?(segment, "s") and not String.ends_with?(segment, "ss") and
          String.length(segment) > 1 ->
        String.trim_trailing(segment, "s")

      true ->
        segment
    end
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
