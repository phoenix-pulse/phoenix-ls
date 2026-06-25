defmodule PhoenixLS.Introspection.Router do
  @moduledoc """
  Source-only extraction helpers for Phoenix router facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Router.Args
  alias PhoenixLS.Introspection.Router.Path, as: RouterPath
  alias PhoenixLS.Introspection.Router.Resource
  alias PhoenixLS.Introspection.Source

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

  defmodule Pipeline do
    @moduledoc """
    Typed Phoenix router pipeline fact payload.
    """

    @enforce_keys [:router, :name, :formats]
    defstruct [:router, :name, :formats]
  end

  @route_macros [:connect, :delete, :get, :head, :live, :options, :patch, :post, :put, :trace]
  @match_route_verbs [:connect, :delete, :get, :head, :options, :patch, :post, :put, :trace]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> Source.top_level_expressions()
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
          |> Source.top_level_expressions()
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
         {:pipeline, meta, args},
         router,
         uri,
         provenance,
         _scope_module,
         _scope_path,
         _helper_segments,
         pipelines,
         _live_session
       ) do
    case pipeline_fact(router, meta, args, uri, provenance) do
      {:ok, fact} -> {[fact], pipelines}
      :error -> {[], pipelines}
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
          |> Source.top_level_expressions()
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
         {:match, meta, args},
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
      match_route_facts(
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

  defp pipeline_fact(router, meta, [name_ast, [do: block]], uri, provenance) do
    case pipeline_name(name_ast) do
      nil ->
        :error

      name ->
        {:ok,
         Fact.new!(
           kind: :pipeline,
           id: "#{router}:pipeline:#{name}",
           uri: uri,
           range: Source.source_range(meta),
           provenance: provenance,
           data: %Pipeline{
             router: router,
             name: name,
             formats: pipeline_formats(block)
           }
         )}
    end
  end

  defp pipeline_fact(_router, _meta, _args, _uri, _provenance), do: :error

  defp pipeline_formats(block) do
    block
    |> Source.top_level_expressions()
    |> Enum.flat_map(&accepted_formats/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp accepted_formats({:plug, _meta, [:accepts, formats_ast]}) do
    case Source.static_literal(formats_ast) do
      {:ok, formats} when is_list(formats) -> Enum.filter(formats, &is_binary/1)
      _not_static_formats -> []
    end
  end

  defp accepted_formats(_expression), do: []

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
      {:ok, module, RouterPath.join(current_path, path),
       scope_helper_segments(helper_segments, path, opts), block}
    end
  end

  defp parse_scope_args([path, [do: block]]) when is_binary(path) do
    {:ok, path, :inherit_scope_module, [], block}
  end

  defp parse_scope_args([path, opts, [do: block]]) when is_binary(path) and is_list(opts) do
    if Args.options_arg?(opts) do
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
    if Args.options_arg?(opts) do
      {:ok, path, module_ast, opts, block}
    else
      :error
    end
  end

  defp parse_scope_args([opts, [do: block]]) when is_list(opts) do
    if Args.options_arg?(opts) do
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
      {:ok, helper} -> current_segments ++ RouterPath.helper_segments_from_value(helper)
      :error -> current_segments ++ RouterPath.helper_segments_from_path(path)
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
      full_path = RouterPath.join(scope_path, path)
      helper_base = RouterPath.helper_base(helper_segments, path)

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
         RouterPath.helper_prefix(helper_segments),
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

  defp match_route_facts(
         meta,
         [verb_ast, path, plug_ast | rest],
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
    verb_ast
    |> match_verbs()
    |> Enum.flat_map(fn verb ->
      case route_fact(
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
           ) do
        {:ok, fact} -> [fact]
        :error -> []
      end
    end)
  end

  defp match_route_facts(
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

  defp match_verbs(:*), do: [:match]

  defp match_verbs(verb) when verb in @match_route_verbs, do: [verb]

  defp match_verbs(verbs) when is_list(verbs) do
    verbs
    |> Enum.flat_map(&match_verbs/1)
    |> Enum.uniq()
  end

  defp match_verbs(_verb), do: []

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
           Resource.options(path, rest) do
      base_path = RouterPath.join(scope_path, path)
      route_helper_segments = helper_segments ++ resource_helper_segments
      helper_base = RouterPath.helper_base_from_segments(route_helper_segments)
      helper_prefix = RouterPath.helper_prefix(helper_segments)

      route_facts =
        actions
        |> Enum.flat_map(&Resource.route_specs(base_path, &1, param, singleton?))
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
          Resource.nested_scope_path(base_path, resource_helper_segments, param, singleton?),
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
      range: Source.source_range(meta),
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
        path_params: RouterPath.path_params(full_path),
        pipelines: pipelines,
        live_session: live_session
      }
    )
  end

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
    |> Source.top_level_expressions()
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

  defp route_action(:forward, _rest), do: {:ok, nil}
  defp route_action(_verb, [action | _rest]) when is_atom(action), do: {:ok, action}
  defp route_action(_verb, []), do: {:ok, nil}
  defp route_action(_verb, _rest), do: :error

  defp route_id(router, verb, path, plug, nil), do: "#{router}:#{verb}:#{path}:#{plug}"

  defp route_id(router, verb, path, plug, action),
    do: "#{router}:#{verb}:#{path}:#{plug}:#{action}"

  defp scoped_alias(ast, nil), do: Source.alias_to_string(ast)

  defp scoped_alias(ast, scope_module) do
    with {:ok, module} <- Source.alias_to_string(ast) do
      if String.starts_with?(module, scope_module <> ".") or module == scope_module do
        {:ok, module}
      else
        {:ok, scope_module <> "." <> module}
      end
    end
  end
end
