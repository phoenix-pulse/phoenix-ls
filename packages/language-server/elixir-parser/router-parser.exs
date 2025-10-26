#!/usr/bin/env elixir

# Phoenix Pulse - Router Parser
# Parses Phoenix router using Elixir's AST
# Returns JSON with route metadata

defmodule PhoenixPulse.RouterParser do
  @moduledoc """
  Parses Phoenix router files and extracts route metadata.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        routes: [],
        file_path: file_path
      }

      result = extract_routes(ast, metadata, %{scope_path: "", alias: nil, pipeline: nil})

      # Output JSON to stdout
      to_json(result)
    rescue
      e ->
        # Return error as JSON
        to_json(%{
          error: true,
          message: Exception.message(e),
          type: e.__struct__ |> to_string()
        })
    end
  end

  # Extract routes by manually walking the AST
  defp extract_routes({:__block__, _, statements}, metadata, context) do
    # Block of statements - process each
    Enum.reduce(statements, metadata, fn statement, acc ->
      extract_routes(statement, acc, context)
    end)
  end

  defp extract_routes({:defmodule, _, [_module_name, [do: block]]}, metadata, context) do
    # Process module body
    extract_routes(block, metadata, context)
  end

  defp extract_routes({:scope, _meta, args}, metadata, context) do
    # Extract scope path and options
    {scope_path, opts, do_block} = parse_scope_args(args)

    # Build new context with scope information
    new_context = %{
      scope_path: merge_paths(context.scope_path, scope_path),
      alias: Keyword.get(opts, :as, context.alias),
      pipeline: context.pipeline
    }

    # Process do block with new context
    if do_block do
      extract_routes(do_block, metadata, new_context)
    else
      metadata
    end
  end

  defp extract_routes({:pipe_through, _, [_pipeline_atom]}, metadata, _context) do
    # Note: pipe_through state would need to be threaded through context
    # For now, we just return unchanged metadata
    metadata
  end

  defp extract_routes({:pipeline, _meta, [_name, [do: block]]}, metadata, context) do
    # Process pipeline block (just traverse it, don't change context)
    extract_routes(block, metadata, context)
  end

  defp extract_routes({verb, meta, args}, metadata, context)
      when verb in [:get, :post, :put, :patch, :delete, :options, :head] do
    case parse_route_args(args) do
      {:ok, route_path, controller, action, opts} ->
        line = Keyword.get(meta, :line, 0)
        route = build_route(
          verb |> to_string() |> String.upcase(),
          route_path,
          controller,
          action,
          opts,
          context,
          line
        )
        %{metadata | routes: [route | metadata.routes]}

      _ ->
        metadata
    end
  end

  defp extract_routes({:live, meta, args}, metadata, context) do
    case parse_live_route_args(args) do
      {:ok, route_path, live_module, live_action, opts} ->
        line = Keyword.get(meta, :line, 0)
        route = build_live_route(
          route_path,
          live_module,
          live_action,
          opts,
          context,
          line
        )
        %{metadata | routes: [route | metadata.routes]}

      _ ->
        metadata
    end
  end

  defp extract_routes({:resources, meta, args}, metadata, context) do
    case parse_resources_args(args) do
      {:ok, route_path, controller, opts, do_block} ->
        line = Keyword.get(meta, :line, 0)
        routes = build_resource_routes(
          route_path,
          controller,
          opts,
          context,
          line
        )

        new_metadata = %{metadata | routes: routes ++ metadata.routes}

        # Process nested resources if do block exists
        if do_block do
          # Create resource context for nested routes
          full_path = merge_paths(context.scope_path, route_path)
          param = Keyword.get(opts, :param, "id") |> to_string()

          nested_context = %{
            context |
            scope_path: "#{full_path}/:#{param}"
          }

          extract_routes(do_block, new_metadata, nested_context)
        else
          new_metadata
        end

      _ ->
        metadata
    end
  end

  defp extract_routes({:forward, meta, args}, metadata, context) do
    case parse_forward_args(args) do
      {:ok, route_path, forward_to, opts} ->
        line = Keyword.get(meta, :line, 0)
        route = build_forward_route(
          route_path,
          forward_to,
          opts,
          context,
          line
        )
        %{metadata | routes: [route | metadata.routes]}

      _ ->
        metadata
    end
  end

  # Ignore other nodes
  defp extract_routes(_node, metadata, _context) do
    metadata
  end

  # Parse scope arguments
  defp parse_scope_args(args) do
    case args do
      # scope "/path", do: ...
      [path_str, [do: block]] when is_binary(path_str) ->
        {path_str, [], block}

      # scope "/path", Module, do: ...
      [path_str, _module_alias, [do: block]] when is_binary(path_str) ->
        {path_str, [], block}

      # scope "/path", Module, [opts], do: ...
      [path_str, _module_alias, opts, [do: block]] when is_binary(path_str) and is_list(opts) ->
        {path_str, opts, block}

      # scope "/path", [opts], do: ...
      [path_str, opts, [do: block]] when is_binary(path_str) and is_list(opts) ->
        {path_str, opts, block}

      # scope do: ...
      [[do: block]] ->
        {"", [], block}

      # scope [opts], do: ...
      [opts, [do: block]] when is_list(opts) ->
        {Keyword.get(opts, :path, ""), opts, block}

      _ ->
        {"", [], nil}
    end
  end

  # Parse basic route arguments: "/path", Controller, :action
  defp parse_route_args(args) do
    case args do
      [path_str, controller_alias, action_atom] when is_binary(path_str) and is_atom(action_atom) ->
        {:ok, path_str, module_to_string(controller_alias), to_string(action_atom), []}

      [path_str, controller_alias, action_atom, opts] when is_binary(path_str) and is_atom(action_atom) and is_list(opts) ->
        {:ok, path_str, module_to_string(controller_alias), to_string(action_atom), opts}

      _ ->
        :error
    end
  end

  # Parse live route arguments: "/path", LiveModule, :action
  defp parse_live_route_args(args) do
    case args do
      [path_str, live_module] when is_binary(path_str) ->
        {:ok, path_str, module_to_string(live_module), nil, []}

      [path_str, live_module, action_atom] when is_binary(path_str) and is_atom(action_atom) ->
        {:ok, path_str, module_to_string(live_module), to_string(action_atom), []}

      [path_str, live_module, action_atom, opts] when is_binary(path_str) and is_atom(action_atom) and is_list(opts) ->
        {:ok, path_str, module_to_string(live_module), to_string(action_atom), opts}

      _ ->
        :error
    end
  end

  # Parse resources arguments: "/users", UserController, (optional opts), (optional do: block)
  defp parse_resources_args(args) do
    case args do
      [path_str, controller_alias] when is_binary(path_str) ->
        {:ok, path_str, module_to_string(controller_alias), [], nil}

      [path_str, controller_alias, opts] when is_binary(path_str) and is_list(opts) ->
        # Check if it has a do block
        do_block = Keyword.get(opts, :do, nil)
        clean_opts = Keyword.delete(opts, :do)
        {:ok, path_str, module_to_string(controller_alias), clean_opts, do_block}

      [path_str, controller_alias, opts, [do: block]] when is_binary(path_str) and is_list(opts) ->
        {:ok, path_str, module_to_string(controller_alias), opts, block}

      _ ->
        :error
    end
  end

  # Parse forward arguments: "/path", Module
  defp parse_forward_args(args) do
    case args do
      [path_str, module_alias] when is_binary(path_str) ->
        {:ok, path_str, module_to_string(module_alias), []}

      [path_str, module_alias, opts] when is_binary(path_str) and is_list(opts) ->
        {:ok, path_str, module_to_string(module_alias), opts}

      _ ->
        :error
    end
  end

  # Build route metadata
  defp build_route(verb, route_path, controller, action, opts, context, line) do
    full_path = merge_paths(context.scope_path, route_path)
    params = extract_path_params(full_path)
    alias_str = Keyword.get(opts, :as, context.alias)

    %{
      verb: verb,
      path: full_path,
      controller: controller,
      action: action,
      line: line,
      params: params,
      alias: alias_str,
      pipeline: context.pipeline,
      scope_path: context.scope_path,
      is_resource: false
    }
  end

  # Build live route metadata
  defp build_live_route(route_path, live_module, live_action, opts, context, line) do
    full_path = merge_paths(context.scope_path, route_path)
    params = extract_path_params(full_path)
    alias_str = Keyword.get(opts, :as, context.alias)

    %{
      verb: "LIVE",
      path: full_path,
      live_module: live_module,
      live_action: live_action,
      line: line,
      params: params,
      alias: alias_str,
      pipeline: context.pipeline,
      scope_path: context.scope_path,
      is_resource: false
    }
  end

  # Build forward route metadata
  defp build_forward_route(route_path, forward_to, opts, context, line) do
    full_path = merge_paths(context.scope_path, route_path)
    params = extract_path_params(full_path)
    alias_str = Keyword.get(opts, :as, context.alias)

    %{
      verb: "FORWARD",
      path: full_path,
      forward_to: forward_to,
      line: line,
      params: params,
      alias: alias_str,
      pipeline: context.pipeline,
      scope_path: context.scope_path,
      is_resource: false
    }
  end

  # Build resource routes (expands to RESTful routes)
  defp build_resource_routes(route_path, controller, opts, context, line) do
    full_path = merge_paths(context.scope_path, route_path)
    only = Keyword.get(opts, :only, nil)
    except = Keyword.get(opts, :except, nil)
    singleton = Keyword.get(opts, :singleton, false)
    param = Keyword.get(opts, :param, "id") |> to_string()
    alias_str = Keyword.get(opts, :as, context.alias)

    # Determine which actions to generate
    all_actions = if singleton do
      [
        {"GET", "", "show"},
        {"GET", "/new", "new"},
        {"POST", "", "create"},
        {"GET", "/edit", "edit"},
        {"PATCH", "", "update"},
        {"PUT", "", "update"},
        {"DELETE", "", "delete"}
      ]
    else
      [
        {"GET", "", "index"},
        {"GET", "/new", "new"},
        {"POST", "", "create"},
        {"GET", "/:#{param}", "show"},
        {"GET", "/:#{param}/edit", "edit"},
        {"PATCH", "/:#{param}", "update"},
        {"PUT", "/:#{param}", "update"},
        {"DELETE", "/:#{param}", "delete"}
      ]
    end

    # Filter by only/except
    filtered_actions = filter_actions(all_actions, only, except)

    # Build route for each action
    Enum.map(filtered_actions, fn {verb, suffix, action} ->
      route_full_path = full_path <> suffix
      params = extract_path_params(route_full_path)

      %{
        verb: verb,
        path: route_full_path,
        controller: controller,
        action: action,
        line: line,
        params: params,
        alias: alias_str,
        pipeline: context.pipeline,
        scope_path: context.scope_path,
        is_resource: true,
        resource_options: %{
          only: only && Enum.map(only, &to_string/1),
          except: except && Enum.map(except, &to_string/1)
        }
      }
    end)
  end

  # Filter actions by only/except options
  defp filter_actions(actions, only, except) do
    cond do
      only != nil ->
        only_strs = Enum.map(only, &to_string/1)
        Enum.filter(actions, fn {_verb, _suffix, action} ->
          action in only_strs
        end)

      except != nil ->
        except_strs = Enum.map(except, &to_string/1)
        Enum.filter(actions, fn {_verb, _suffix, action} ->
          action not in except_strs
        end)

      true ->
        actions
    end
  end

  # Extract path parameters (:id, :slug, etc.)
  defp extract_path_params(path) do
    path
    |> String.split("/")
    |> Enum.filter(&String.starts_with?(&1, ":"))
    |> Enum.map(&String.trim_leading(&1, ":"))
  end

  # Merge scope path with route path
  defp merge_paths("", route_path), do: route_path
  defp merge_paths(scope_path, ""), do: scope_path
  defp merge_paths(scope_path, route_path) do
    # Ensure scope_path doesn't end with / and route_path starts with /
    scope_clean = String.trim_trailing(scope_path, "/")
    route_clean = if String.starts_with?(route_path, "/") do
      route_path
    else
      "/" <> route_path
    end
    scope_clean <> route_clean
  end

  # Convert module alias to string
  defp module_to_string({:__aliases__, _, parts}) do
    Enum.join(parts, ".")
  end

  defp module_to_string(atom) when is_atom(atom) do
    to_string(atom)
  end

  defp module_to_string(other) do
    inspect(other)
  end

  # Simple JSON encoder (avoids dependency on Jason)
  def to_json(data) when is_map(data) do
    pairs = Map.to_list(data) |> Enum.map(fn {k, v} ->
      key_str = if is_atom(k), do: to_string(k), else: k
      ~s("#{key_str}":#{to_json(v)})
    end)
    "{#{Enum.join(pairs, ",")}}"
  end

  def to_json(data) when is_list(data) do
    items = Enum.map(data, &to_json/1)
    "[#{Enum.join(items, ",")}]"
  end

  def to_json(data) when is_binary(data) do
    escaped = data
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")

    ~s("#{escaped}")
  end

  def to_json(data) when is_boolean(data), do: to_string(data)
  def to_json(nil), do: "null"
  def to_json(data) when is_number(data), do: to_string(data)
  def to_json(data) when is_atom(data), do: to_json(to_string(data))
  def to_json(_), do: "null"
end

# Main execution
case System.argv() do
  [file_path] ->
    result = PhoenixPulse.RouterParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.RouterParser.to_json(%{
      error: true,
      message: "Usage: elixir router-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
