#!/usr/bin/env elixir

# Phoenix Pulse - LiveView Parser
# Parses Phoenix LiveView lifecycle functions using Elixir's AST
# Returns JSON with LiveView function metadata

defmodule PhoenixPulse.LiveViewParser do
  @moduledoc """
  Parses Phoenix LiveView modules and extracts all lifecycle functions:
  - mount/3
  - handle_params/3
  - handle_event/3
  - handle_info/2
  - render/1

  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        functions: [],
        file_path: file_path
      }

      result = extract_metadata(ast, metadata)

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

  defp extract_metadata(ast, metadata) do
    # Walk the AST and accumulate metadata
    {_ast, result} = Macro.prewalk(ast, metadata, &process_node/2)
    result
  end

  defp process_node({:defmodule, _meta, [module_alias, [do: _block]]} = node, acc) do
    module_name = module_alias_to_string(module_alias)
    acc = %{acc | module: module_name}
    {node, acc}
  end

  # Parse mount/3: def mount(params, session, socket)
  defp process_node({:def, meta, [{:mount, _fn_meta, [_params, _session, _socket]} | _rest]} = node, acc) do
    line = Keyword.get(meta, :line, 0)
    func = %{
      name: "mount",
      type: "mount",
      line: line,
      module_name: acc.module
    }
    {node, %{acc | functions: [func | acc.functions]}}
  end

  # Parse handle_params/3: def handle_params(params, uri, socket)
  defp process_node({:def, meta, [{:handle_params, _fn_meta, [_params, _uri, _socket]} | _rest]} = node, acc) do
    line = Keyword.get(meta, :line, 0)
    func = %{
      name: "handle_params",
      type: "handle_params",
      line: line,
      module_name: acc.module
    }
    {node, %{acc | functions: [func | acc.functions]}}
  end

  # Parse render/1: def render(assigns)
  defp process_node({:def, meta, [{:render, _fn_meta, [_assigns]} | _rest]} = node, acc) do
    line = Keyword.get(meta, :line, 0)
    func = %{
      name: "render",
      type: "render",
      line: line,
      module_name: acc.module
    }
    {node, %{acc | functions: [func | acc.functions]}}
  end

  # Parse handle_event/3 definitions
  # def handle_event("event_name", params, socket)
  defp process_node({:def, meta, [{:handle_event, _fn_meta, [event_name, _params, _socket]} | _rest]} = node, acc) do
    func = parse_event_function(event_name, meta, acc)
    if func do
      {node, %{acc | functions: [func | acc.functions]}}
    else
      {node, acc}
    end
  end

  # Parse private handle_event/3 definitions
  defp process_node({:defp, meta, [{:handle_event, _fn_meta, [event_name, _params, _socket]} | _rest]} = node, acc) do
    func = parse_event_function(event_name, meta, acc)
    if func do
      {node, %{acc | functions: [func | acc.functions]}}
    else
      {node, acc}
    end
  end

  # Parse handle_info/2 definitions
  # def handle_info(:message, socket)
  # def handle_info({:message, data}, socket)
  defp process_node({:def, meta, [{:handle_info, _fn_meta, [message, _socket]} | _rest]} = node, acc) do
    func = parse_info_function(message, meta, acc)
    if func do
      {node, %{acc | functions: [func | acc.functions]}}
    else
      {node, acc}
    end
  end

  # Parse private handle_info/2 definitions
  defp process_node({:defp, meta, [{:handle_info, _fn_meta, [message, _socket]} | _rest]} = node, acc) do
    func = parse_info_function(message, meta, acc)
    if func do
      {node, %{acc | functions: [func | acc.functions]}}
    else
      {node, acc}
    end
  end

  defp process_node(node, acc) do
    {node, acc}
  end

  defp parse_event_function(event_name, meta, acc) do
    line = Keyword.get(meta, :line, 0)

    # Extract event name
    event_name_str = case event_name do
      {:<<>>, _, parts} when is_list(parts) ->
        # String literal
        extract_string_literal(parts)

      name when is_binary(name) ->
        # Already a string
        name

      name when is_atom(name) ->
        # Atom
        atom_to_name(name)

      _ ->
        # Unknown pattern, skip
        nil
    end

    if event_name_str do
      %{
        name: event_name_str,
        type: "handle_event",
        event_name: event_name_str,
        line: line,
        module_name: acc.module
      }
    else
      nil
    end
  end

  defp parse_info_function(message, meta, acc) do
    line = Keyword.get(meta, :line, 0)

    # Extract message pattern
    message_name = case message do
      # Atom: :message
      name when is_atom(name) ->
        atom_to_name(name)

      # Binary/String literal
      {:<<>>, _, _parts} = str_ast ->
        # Try to extract the string value
        try do
          {value, _} = Code.eval_quoted(str_ast)
          value
        rescue
          _ -> nil
        end

      # String literal (already evaluated)
      name when is_binary(name) ->
        name

      # Tuple: {:message, data}
      {:{}, _, [first_elem | _rest]} when is_atom(first_elem) ->
        atom_to_name(first_elem)

      # Two-element tuple: {:message, data}
      {first_elem, _second} when is_atom(first_elem) ->
        atom_to_name(first_elem)

      _ ->
        # Unknown pattern, skip
        nil
    end

    if message_name do
      %{
        name: message_name,
        type: "handle_info",
        event_name: message_name,
        line: line,
        module_name: acc.module
      }
    else
      nil
    end
  end

  # Extract string from AST string parts
  defp extract_string_literal(parts) do
    parts
    |> Enum.map(fn
      str when is_binary(str) -> str
      {:"::", _, [str, {:binary, _, _}]} when is_binary(str) -> str
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp module_alias_to_string({:__aliases__, _, parts}) do
    Enum.join(parts, ".")
  end

  defp module_alias_to_string(atom) when is_atom(atom) do
    to_string(atom)
  end

  defp module_alias_to_string(_), do: "Unknown"

  defp atom_to_name(atom) when is_atom(atom) do
    atom |> to_string() |> String.trim_leading(":")
  end

  defp atom_to_name(str) when is_binary(str), do: str
  defp atom_to_name(other), do: inspect(other)

  # Simple JSON encoder (avoids dependency on Jason)
  def to_json(data) when is_map(data) do
    pairs = Enum.map(data, fn {k, v} ->
      ~s("#{k}":#{to_json(v)})
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
    result = PhoenixPulse.LiveViewParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.LiveViewParser.to_json(%{
      error: true,
      message: "Usage: elixir liveview-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
