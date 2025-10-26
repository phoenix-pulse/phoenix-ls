#!/usr/bin/env elixir

# Phoenix Pulse - Events Parser
# Parses handle_event/3 and handle_info/2 using Elixir's AST
# Returns JSON with event metadata

defmodule PhoenixPulse.EventsParser do
  @moduledoc """
  Parses Phoenix LiveView event handlers and extracts metadata.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        events: [],
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

  # Parse handle_event/3 definitions
  # def handle_event("event_name", params, socket)
  defp process_node({:def, meta, [{:handle_event, _fn_meta, [event_name, params, _socket]} | _rest]} = node, acc) do
    event = parse_event_function(:handle_event, event_name, params, meta, acc)
    if event do
      {node, %{acc | events: [event | acc.events]}}
    else
      {node, acc}
    end
  end

  # Parse private handle_event/3 definitions
  defp process_node({:defp, meta, [{:handle_event, _fn_meta, [event_name, params, _socket]} | _rest]} = node, acc) do
    event = parse_event_function(:handle_event, event_name, params, meta, acc)
    if event do
      {node, %{acc | events: [event | acc.events]}}
    else
      {node, acc}
    end
  end

  # Parse handle_info/2 definitions
  # def handle_info(:message, socket)
  # def handle_info({:message, data}, socket)
  defp process_node({:def, meta, [{:handle_info, _fn_meta, [message, _socket]} | _rest]} = node, acc) do
    event = parse_info_function(message, meta, acc)
    if event do
      {node, %{acc | events: [event | acc.events]}}
    else
      {node, acc}
    end
  end

  # Parse private handle_info/2 definitions
  defp process_node({:defp, meta, [{:handle_info, _fn_meta, [message, _socket]} | _rest]} = node, acc) do
    event = parse_info_function(message, meta, acc)
    if event do
      {node, %{acc | events: [event | acc.events]}}
    else
      {node, acc}
    end
  end

  defp process_node(node, acc) do
    {node, acc}
  end

  defp parse_event_function(:handle_event, event_name, params, meta, acc) do
    line = Keyword.get(meta, :line, 0)

    # Extract event name
    {name, name_kind} = case event_name do
      {:<<>>, _, parts} when is_list(parts) ->
        # String literal
        name = extract_string_literal(parts)
        {name, "string"}

      name when is_binary(name) ->
        # Already a string
        {name, "string"}

      name when is_atom(name) ->
        # Atom
        {atom_to_name(name), "atom"}

      _ ->
        # Unknown pattern, skip
        {nil, nil}
    end

    if name do
      %{
        name: name,
        module_name: acc.module,
        line: line,
        params: stringify_params(params),
        kind: "handle_event",
        name_kind: name_kind,
        doc: nil  # TODO: Extract @doc if needed
      }
    else
      nil
    end
  end

  defp parse_info_function(message, meta, acc) do
    line = Keyword.get(meta, :line, 0)

    # Extract message pattern
    {name, name_kind, params} = case message do
      # Atom: :message
      name when is_atom(name) ->
        {atom_to_name(name), "atom", ":atom"}

      # Binary/String literal
      {:<<>>, _, _parts} = str_ast ->
        # Try to extract the string value
        try do
          {value, _} = Code.eval_quoted(str_ast)
          {value, "string", "\"string\""}
        rescue
          _ -> {nil, nil, nil}
        end

      # String literal (already evaluated)
      name when is_binary(name) ->
        {name, "string", "\"string\""}

      # Tuple: {:message, data}
      {:{}, _, [first_elem | _rest]} when is_atom(first_elem) ->
        {atom_to_name(first_elem), "atom", stringify_params(message)}

      # Two-element tuple: {:message, data}
      {first_elem, _second} when is_atom(first_elem) ->
        {atom_to_name(first_elem), "atom", stringify_params(message)}

      _ ->
        # Unknown pattern, skip
        {nil, nil, nil}
    end

    if name do
      %{
        name: name,
        module_name: acc.module,
        line: line,
        params: params,
        kind: "handle_info",
        name_kind: name_kind,
        doc: nil
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

  # Convert params AST to a readable string
  defp stringify_params({name, _meta, nil}) when is_atom(name) do
    atom_to_name(name)
  end

  defp stringify_params({name, _meta, _context}) when is_atom(name) do
    atom_to_name(name)
  end

  defp stringify_params({:%{}, _meta, pairs}) do
    # Map pattern
    fields = Enum.map(pairs, fn
      {key, _value} -> inspect(key)
      other -> inspect(other)
    end)
    "%{#{Enum.join(fields, ", ")}}"
  end

  defp stringify_params({:{}, _meta, elements}) do
    # Tuple pattern
    "{#{Enum.join(Enum.map(elements, &stringify_params/1), ", ")}}"
  end

  defp stringify_params({a, b}) do
    # Two-element tuple
    "{#{stringify_params(a)}, #{stringify_params(b)}}"
  end

  defp stringify_params(atom) when is_atom(atom) do
    atom_to_name(atom)
  end

  defp stringify_params(other) do
    inspect(other)
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
    result = PhoenixPulse.EventsParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.EventsParser.to_json(%{
      error: true,
      message: "Usage: elixir events-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
