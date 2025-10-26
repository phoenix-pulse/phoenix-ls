#!/usr/bin/env elixir

# Phoenix Pulse - Controller Parser
# Parses Phoenix controller files and extracts render() call metadata
# Returns JSON with controller actions, templates, and assigns

defmodule PhoenixPulse.ControllerParser do
  @moduledoc """
  Parses Phoenix controller files and extracts render() calls.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        renders: [],
        file_path: file_path
      }

      result = extract_controller_info(ast, metadata)

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

  # Extract controller info by walking the AST
  defp extract_controller_info({:defmodule, _meta, [module_name, [do: block]]}, metadata) do
    module = module_to_string(module_name)
    new_metadata = %{metadata | module: module}
    process_module_body(block, new_metadata)
  end

  defp extract_controller_info(_node, metadata) do
    metadata
  end

  # Process module body (list of function definitions)
  defp process_module_body({:__block__, _, statements}, metadata) do
    Enum.reduce(statements, metadata, fn statement, acc ->
      process_statement(statement, acc)
    end)
  end

  defp process_module_body(statement, metadata) do
    process_statement(statement, metadata)
  end

  # Process individual statements (function definitions)
  defp process_statement({:def, meta, [signature, [do: body]]}, metadata) do
    action_name = extract_function_name(signature)
    line = Keyword.get(meta, :line, 0)

    # Extract render calls from function body
    renders = extract_render_calls(body, action_name, line)

    %{metadata | renders: metadata.renders ++ renders}
  end

  defp process_statement({:defp, meta, [signature, [do: body]]}, metadata) do
    # Also process private functions (might contain render calls)
    action_name = extract_function_name(signature)
    line = Keyword.get(meta, :line, 0)

    renders = extract_render_calls(body, action_name, line)

    %{metadata | renders: metadata.renders ++ renders}
  end

  defp process_statement(_node, metadata) do
    metadata
  end

  # Extract function name from signature
  defp extract_function_name({name, _meta, _args}) when is_atom(name) do
    to_string(name)
  end

  defp extract_function_name(_signature) do
    "unknown"
  end

  # Extract render() calls from function body
  defp extract_render_calls(body, action_name, _action_line) do
    render_calls = []
    walk_ast(body, render_calls, action_name)
  end

  # Walk AST looking for render() calls
  defp walk_ast({:render, meta, args}, renders, action_name) when is_list(args) do
    # Found a render call!
    line = Keyword.get(meta, :line, 0)

    case parse_render_args(args) do
      {:ok, render_info} ->
        render = Map.merge(render_info, %{
          action: action_name,
          line: line
        })
        [render | renders]

      :error ->
        renders
    end
  end

  defp walk_ast({_node, _meta, children}, renders, action_name) when is_list(children) do
    # Recursively walk child nodes
    Enum.reduce(children, renders, fn child, acc ->
      walk_ast(child, acc, action_name)
    end)
  end

  defp walk_ast(tuple, renders, action_name) when is_tuple(tuple) do
    # For other tuple forms, check each element
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(renders, fn element, acc ->
      walk_ast(element, acc, action_name)
    end)
  end

  defp walk_ast(list, renders, action_name) when is_list(list) do
    # Walk list elements
    Enum.reduce(list, renders, fn element, acc ->
      walk_ast(element, acc, action_name)
    end)
  end

  defp walk_ast(_node, renders, _action_name) do
    # Base case: not a traversable node
    renders
  end

  # Parse render() arguments
  # Patterns:
  # - render(conn, :template)
  # - render(conn, :template, assigns)
  # - render(conn, ViewModule, :template)
  # - render(conn, ViewModule, :template, assigns)
  defp parse_render_args(args) do
    case args do
      # render(conn, :template)
      [_conn, template] when is_atom(template) or is_binary(template) ->
        {:ok, %{
          view_module: nil,
          template_name: normalize_template(template),
          template_format: nil,
          assigns: []
        }}

      # render(conn, :template, assigns)
      [_conn, template, assigns_list] when is_atom(template) or is_binary(template) ->
        assigns = extract_assigns(assigns_list)
        {:ok, %{
          view_module: nil,
          template_name: normalize_template(template),
          template_format: nil,
          assigns: assigns
        }}

      # render(conn, ViewModule, :template) or render(conn, ViewModule, :template, assigns)
      [_conn, view_module_ast, template | rest] ->
        if looks_like_module_ast?(view_module_ast) do
          view_module = module_to_string(view_module_ast)
          assigns = if length(rest) > 0, do: extract_assigns(hd(rest)), else: []

          {:ok, %{
            view_module: view_module,
            template_name: normalize_template(template),
            template_format: nil,
            assigns: assigns
          }}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Check if AST node looks like a module alias
  defp looks_like_module_ast?({:__aliases__, _, _}), do: true
  defp looks_like_module_ast?(atom) when is_atom(atom) do
    str = to_string(atom)
    # Check if starts with uppercase (Elixir convention for modules)
    String.match?(str, ~r/^[A-Z]/)
  end
  defp looks_like_module_ast?(_), do: false

  # Normalize template argument (handle atoms, strings, with/without format)
  defp normalize_template(atom) when is_atom(atom) do
    to_string(atom)
  end

  defp normalize_template(string) when is_binary(string) do
    string
  end

  defp normalize_template(_), do: "unknown"

  # Extract assigns from keyword list
  # Pattern: [user: user, posts: posts, page_title: "Title"]
  defp extract_assigns(assigns_list) do
    case assigns_list do
      # Keyword list in AST form
      list when is_list(list) ->
        for {key, value} <- list, is_atom(key) do
          %{
            key: to_string(key),
            value: value_to_string(value)
          }
        end

      # Not a keyword list
      _ ->
        []
    end
  end

  # Convert AST value to string representation
  defp value_to_string({:@, _, [{name, _, _}]}) when is_atom(name) do
    "@#{name}"
  end

  defp value_to_string({name, _, nil}) when is_atom(name) do
    to_string(name)
  end

  defp value_to_string({name, _, _}) when is_atom(name) do
    to_string(name)
  end

  defp value_to_string(string) when is_binary(string) do
    "\"#{string}\""
  end

  defp value_to_string(atom) when is_atom(atom) do
    to_string(atom)
  end

  defp value_to_string(number) when is_number(number) do
    to_string(number)
  end

  defp value_to_string({_, _, _} = _ast) do
    # Complex expression - just indicate it's an expression
    "(expr)"
  end

  defp value_to_string(_) do
    "(unknown)"
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
    result = PhoenixPulse.ControllerParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.ControllerParser.to_json(%{
      error: true,
      message: "Usage: elixir controller-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
