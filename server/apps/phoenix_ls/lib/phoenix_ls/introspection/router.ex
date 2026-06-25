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
      :helper_prefix,
      :path_params,
      :pipelines,
      :live_session
    ]
  end

  @route_macros [:connect, :delete, :get, :head, :live, :options, :patch, :post, :put, :trace]
  @resource_actions [:index, :new, :edit, :show, :create, :update, :delete]
  @singleton_resource_actions [:show, :new, :edit, :create, :update, :delete]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> top_level_expressions()
    |> collect_expressions(module, uri, provenance, nil, "", [], [], nil)
  end

  defp collect_expressions(
         expressions,
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         helper_segments,
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
          helper_segments,
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
         helper_segments,
         pipelines,
         live_session
       ) do
    case scope_context(args, scope_path, scope_module, helper_segments) do
      {:ok, next_scope_module, next_scope_path, next_helper_segments, block} ->
        facts =
          block
          |> top_level_expressions()
          |> collect_expressions(
            router,
            uri,
            provenance,
            next_scope_module,
            next_scope_path,
            next_helper_segments,
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
         _helper_segments,
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
         helper_segments,
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
            helper_segments,
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
         helper_segments,
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
        helper_segments,
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
         helper_segments,
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
           helper_segments,
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
         helper_segments,
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
           helper_segments,
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
         _helper_segments,
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

  defp scope_context(args, current_path, current_module, helper_segments) do
    with {:ok, path, module_ast, opts, block} <- parse_scope_args(args),
         {:ok, module} <- scope_module(module_ast, current_module, opts) do
      {:ok, module, join_paths(current_path, path),
       scope_helper_segments(helper_segments, path, opts), block}
    end
  end

  defp parse_scope_args([path, [do: block]]) when is_binary(path) do
    {:ok, path, :inherit_scope_module, [], block}
  end

  defp parse_scope_args([path, opts, [do: block]]) when is_binary(path) and is_list(opts) do
    if options_arg?(opts) do
      {:ok, path, :inherit_scope_module, opts, block}
    else
      :error
    end
  end

  defp parse_scope_args([path, module_ast, [do: block]]) when is_binary(path) do
    {:ok, path, module_ast, [], block}
  end

  defp parse_scope_args([path, module_ast, opts, [do: block]])
       when is_binary(path) and is_list(opts) do
    if options_arg?(opts) do
      {:ok, path, module_ast, opts, block}
    else
      :error
    end
  end

  defp parse_scope_args([opts, [do: block]]) when is_list(opts) do
    if options_arg?(opts) do
      {:ok, Keyword.get(opts, :path, ""), :inherit_scope_module, opts, block}
    else
      :error
    end
  end

  defp parse_scope_args(_args), do: :error

  defp scope_module(:inherit_scope_module, current_module, opts) do
    case Keyword.fetch(opts, :alias) do
      {:ok, false} -> {:ok, nil}
      {:ok, module_ast} -> scoped_alias(module_ast, current_module)
      :error -> {:ok, current_module}
    end
  end

  defp scope_module(module_ast, current_module, opts) do
    case Keyword.get(opts, :alias, true) do
      false -> {:ok, nil}
      _other -> scoped_alias(module_ast, current_module)
    end
  end

  defp scope_helper_segments(current_segments, path, opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, false} -> current_segments
      {:ok, nil} -> current_segments
      {:ok, helper} -> current_segments ++ helper_segments_from_value(helper)
      :error -> current_segments ++ helper_segments_from_path(path)
    end
  end

  defp route_fact(
         verb,
         meta,
         [path, plug_ast | rest],
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         helper_segments,
         pipelines,
         live_session
       )
       when is_binary(path) do
    with {:ok, plug} <- scoped_alias(plug_ast, scope_module),
         {:ok, action} <- route_action(verb, rest) do
      full_path = join_paths(scope_path, path)
      helper_base = helper_base(helper_segments, path)

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
         helper_base,
         helper_prefix(helper_segments),
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
         _helper_segments,
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
         helper_segments,
         pipelines,
         live_session
       )
       when is_binary(path) do
    with {:ok, controller} <- scoped_alias(controller_ast, scope_module),
         {:ok, actions, param, singleton?, resource_helper_segments, block} <-
           resource_options(path, rest) do
      base_path = join_paths(scope_path, path)
      route_helper_segments = helper_segments ++ resource_helper_segments
      helper_base = helper_base_from_segments(route_helper_segments)
      helper_prefix = helper_prefix(helper_segments)

      route_facts =
        actions
        |> Enum.flat_map(&resource_route_specs(base_path, &1, param, singleton?))
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
            helper_base,
            helper_prefix,
            pipelines,
            live_session
          )
        end)

      route_facts ++
        nested_resource_facts(
          block,
          router,
          uri,
          provenance,
          scope_module,
          nested_resource_scope_path(base_path, resource_helper_segments, param, singleton?),
          route_helper_segments,
          pipelines,
          live_session
        )
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
         _helper_segments,
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
         helper_base,
         helper_prefix,
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
        helper_base: helper_base,
        helper_prefix: helper_prefix,
        path_params: path_params(full_path),
        pipelines: pipelines,
        live_session: live_session
      }
    )
  end

  defp resource_options(path, rest) do
    with {:ok, opts, block} <- resource_args(rest) do
      singleton? = Keyword.get(opts, :singleton, false) == true
      valid_actions = if singleton?, do: @singleton_resource_actions, else: @resource_actions

      {:ok, actions(opts, valid_actions), resource_param(opts), singleton?,
       resource_helper_segments(path, opts), block}
    end
  end

  defp resource_args([]), do: {:ok, [], nil}

  defp resource_args([[do: block]]), do: {:ok, [], block}

  defp resource_args([opts]) when is_list(opts) do
    if options_arg?(opts) do
      {:ok, opts, nil}
    else
      :error
    end
  end

  defp resource_args([opts, [do: block]]) when is_list(opts) do
    if options_arg?(opts) do
      {:ok, opts, block}
    else
      :error
    end
  end

  defp resource_args(_rest), do: :error

  defp actions(opts, valid_actions) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    requested_actions =
      case only do
        actions when is_list(actions) -> actions
        nil -> valid_actions
        _other -> []
      end

    requested_actions
    |> Enum.filter(&(&1 in valid_actions))
    |> Enum.reject(&(&1 in except_actions(except)))
  end

  defp except_actions(except) when is_list(except), do: except
  defp except_actions(_except), do: []

  defp resource_param(opts) do
    case Keyword.get(opts, :param, "id") do
      param when is_binary(param) -> param
      param when is_atom(param) -> Atom.to_string(param)
      _other -> "id"
    end
  end

  defp resource_helper_segments(path, opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, nil} -> []
      {:ok, false} -> []
      {:ok, helper} -> helper_segments_from_value(helper)
      :error -> helper_segments_from_path(path)
    end
  end

  defp resource_route_specs(base_path, :index, _param, false), do: [{:get, base_path, :index}]
  defp resource_route_specs(_base_path, :index, _param, true), do: []

  defp resource_route_specs(base_path, :new, _param, _singleton?),
    do: [{:get, join_paths(base_path, "new"), :new}]

  defp resource_route_specs(base_path, :edit, _param, true),
    do: [{:get, join_paths(base_path, "edit"), :edit}]

  defp resource_route_specs(base_path, :edit, param, false),
    do: [{:get, join_paths(base_path, ":#{param}/edit"), :edit}]

  defp resource_route_specs(base_path, :show, _param, true),
    do: [{:get, base_path, :show}]

  defp resource_route_specs(base_path, :show, param, false),
    do: [{:get, join_paths(base_path, ":#{param}"), :show}]

  defp resource_route_specs(base_path, :create, _param, _singleton?),
    do: [{:post, base_path, :create}]

  defp resource_route_specs(base_path, :update, _param, true) do
    [{:patch, base_path, :update}, {:put, base_path, :update}]
  end

  defp resource_route_specs(base_path, :update, param, false) do
    path = join_paths(base_path, ":#{param}")
    [{:patch, path, :update}, {:put, path, :update}]
  end

  defp resource_route_specs(base_path, :delete, _param, true), do: [{:delete, base_path, :delete}]

  defp resource_route_specs(base_path, :delete, param, false),
    do: [{:delete, join_paths(base_path, ":#{param}"), :delete}]

  defp nested_resource_facts(
         nil,
         _router,
         _uri,
         _provenance,
         _scope_module,
         _scope_path,
         _helper_segments,
         _pipelines,
         _live_session
       ),
       do: []

  defp nested_resource_facts(
         block,
         router,
         uri,
         provenance,
         scope_module,
         scope_path,
         helper_segments,
         pipelines,
         live_session
       ) do
    block
    |> top_level_expressions()
    |> collect_expressions(
      router,
      uri,
      provenance,
      scope_module,
      scope_path,
      helper_segments,
      pipelines,
      live_session
    )
  end

  defp nested_resource_scope_path(base_path, _resource_helper_segments, _param, true),
    do: base_path

  defp nested_resource_scope_path(base_path, resource_helper_segments, param, false) do
    join_paths(base_path, ":#{nested_resource_param(resource_helper_segments, param)}")
  end

  defp nested_resource_param(resource_helper_segments, param) do
    resource_name =
      resource_helper_segments
      |> List.last()
      |> case do
        nil -> "resource"
        name -> name
      end

    "#{resource_name}_#{param}"
  end

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

  defp helper_base(helper_segments, path) do
    helper_base_from_segments(helper_segments ++ helper_segments_from_path(path))
  end

  defp helper_base_from_segments([]), do: "root"

  defp helper_base_from_segments(segments) do
    Enum.join(segments, "_")
  end

  defp helper_prefix([]), do: nil
  defp helper_prefix(segments), do: Enum.join(segments, "_")

  defp helper_segments_from_path(path) do
    path
    |> path_segments()
    |> Enum.reject(&dynamic_path_segment?/1)
    |> Enum.map(&normalize_helper_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&singularize/1)
  end

  defp helper_segments_from_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> helper_segment_from_value()
  end

  defp helper_segments_from_value(value) when is_binary(value) do
    helper_segment_from_value(value)
  end

  defp helper_segments_from_value(_value), do: []

  defp helper_segment_from_value(value) do
    value
    |> normalize_helper_segment()
    |> case do
      "" -> []
      segment -> [segment]
    end
  end

  defp options_arg?(opts) when is_list(opts) do
    not block_arg?(opts) and
      Enum.all?(opts, fn
        {key, _value} when is_atom(key) -> true
        _other -> false
      end)
  end

  defp block_arg?([{:do, _block}]), do: true
  defp block_arg?(_opts), do: false

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
