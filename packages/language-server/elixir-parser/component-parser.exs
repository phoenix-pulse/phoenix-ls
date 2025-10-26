#!/usr/bin/env elixir

# Phoenix Pulse - Component Parser
# Parses Phoenix LiveView components using Elixir's AST
# Returns JSON with component metadata (attrs, slots, functions)

defmodule PhoenixPulse.ComponentParser do
  @moduledoc """
  Parses Phoenix function components and extracts metadata.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        components: [],
        file_path: file_path,
        pending_attrs: [],
        pending_slots: [],
        last_function_name: nil  # Track last function to detect clauses
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

    # Continue walking inside the module
    {node, acc}
  end

  defp process_node({:def, meta, [{name, _fn_meta, [{:assigns, _, _}]}, [do: _body]]} = node, acc) when is_atom(name) do
    # Found a function component: def component_name(assigns)
    line = Keyword.get(meta, :line, 0)

    # Check if this is a new function or another clause of the same function
    last_name = Map.get(acc, :last_function_name)

    if last_name == name do
      # Same function name - this is another clause, skip it
      # Just track that we saw this function again
      {node, Map.put(acc, :last_function_name, name)}
    else
      # Different function - create new component
      component = %{
        name: to_string(name),
        line: line,
        attributes: Map.get(acc, :pending_attrs, []),
        slots: Map.get(acc, :pending_slots, [])
      }

      # Add component and clear pending attrs/slots for next component
      acc = %{acc |
        components: [component | acc.components],
        pending_attrs: [],
        pending_slots: [],
        last_function_name: name
      }

      {node, acc}
    end
  end

  defp process_node({:def, meta, [{name, _fn_meta, [{:=, _, [_pattern, {:assigns, _, _}]}]}, [do: _body]]} = node, acc) when is_atom(name) do
    # Found a function component with pattern matching: def component_name(%{...} = assigns)
    line = Keyword.get(meta, :line, 0)

    # Check if this is a new function or another clause of the same function
    last_name = Map.get(acc, :last_function_name)

    if last_name == name do
      # Same function name - this is another clause, skip it
      {node, Map.put(acc, :last_function_name, name)}
    else
      # Different function - create new component
      component = %{
        name: to_string(name),
        line: line,
        attributes: Map.get(acc, :pending_attrs, []),
        slots: Map.get(acc, :pending_slots, [])
      }

      # Add component and clear pending attrs/slots for next component
      acc = %{acc |
        components: [component | acc.components],
        pending_attrs: [],
        pending_slots: [],
        last_function_name: name
      }

      {node, acc}
    end
  end

  defp process_node({:attr, meta, args} = node, acc) do
    # Parse attr declaration: attr :name, :type, options
    line = Keyword.get(meta, :line, 0)

    attr_info = parse_attr(args, line)
    pending_attrs = [attr_info | Map.get(acc, :pending_attrs, [])]

    {node, Map.put(acc, :pending_attrs, pending_attrs)}
  end

  defp process_node({:slot, meta, args}, acc) do
    # Parse slot declaration: slot :name, options (or slot :name, options do...end)
    line = Keyword.get(meta, :line, 0)

    slot_info = parse_slot(args, line)
    pending_slots = [slot_info | Map.get(acc, :pending_slots, [])]

    # IMPORTANT: Strip the do block from args to prevent Macro.prewalk from
    # descending into it (we already extracted attrs manually in parse_slot)
    stripped_args = case args do
      # Format: [:name, [opts], [do: block]]
      [name_atom, opts, _do_block] ->
        [name_atom, opts]
      # Format: [:name, [opts_with_do]]
      [name_atom, opts] ->
        # Check if opts contains :do
        if Keyword.has_key?(opts, :do) do
          [name_atom, Keyword.delete(opts, :do)]
        else
          args
        end
      other ->
        other
    end

    stripped_node = {:slot, meta, stripped_args}

    {stripped_node, Map.put(acc, :pending_slots, pending_slots)}
  end

  defp process_node(node, acc) do
    # Continue walking
    {node, acc}
  end

  defp parse_attr([name_atom, type_atom | rest], line) when is_atom(name_atom) do
    name = atom_to_name(name_atom)
    type = atom_to_name(type_atom)

    # Parse options (third argument if present)
    opts = case rest do
      [[{_, _} | _] = keyword_list] -> parse_attr_options(keyword_list)
      _ -> %{}
    end

    %{
      name: name,
      type: type,
      line: line,
      required: Map.get(opts, :required, false),
      default: Map.get(opts, :default),
      values: Map.get(opts, :values),
      doc: Map.get(opts, :doc)
    }
  end

  defp parse_attr(_args, line) do
    # Fallback for malformed attr
    %{name: "unknown", type: "any", line: line, required: false}
  end

  defp parse_slot([name_atom | rest], line) when is_atom(name_atom) do
    name = atom_to_name(name_atom)

    # Parse options and extract do block
    # Args can be in two formats:
    # 1. [:name, [opts], [do: block]] - 3 elements
    # 2. [:name, [opts with :do]] - 2 elements (opts contains :do key)
    {opts, do_block} = case rest do
      # Format 1: [:name, [opts], [do: block]]
      [[{_, _} | _] = options, [{:do, block}]] ->
        opts = parse_slot_options(options)
        {opts, block}

      # Format 2: [:name, [opts_with_do]]
      [[{_, _} | _] = keyword_list] ->
        # Separate do block from other options
        do_block = Keyword.get(keyword_list, :do)
        opts = parse_slot_options(keyword_list)
        {opts, do_block}

      _ ->
        {%{}, nil}
    end

    # Extract attrs from do block if present
    attributes = if do_block do
      extract_slot_attrs_from_block(do_block)
    else
      Map.get(opts, :attributes, [])
    end

    %{
      name: name,
      line: line,
      required: Map.get(opts, :required, false),
      doc: Map.get(opts, :doc),
      attributes: attributes
    }
  end

  defp parse_slot(_args, line) do
    %{name: "unknown", line: line, required: false, attributes: []}
  end

  defp extract_slot_attrs_from_block(do_block) do
    # Walk through the do block to find attr declarations
    case do_block do
      # Multiple statements in block: {:__block__, [], [stmt1, stmt2, ...]}
      {:__block__, _, statements} when is_list(statements) ->
        Enum.reduce(statements, [], fn stmt, acc ->
          case stmt do
            {:attr, meta, args} ->
              line = Keyword.get(meta, :line, 0)
              attr_info = parse_attr(args, line)
              [attr_info | acc]
            _ ->
              acc
          end
        end)
        |> Enum.reverse()

      # Single attr in block: {:attr, meta, args}
      {:attr, meta, args} ->
        line = Keyword.get(meta, :line, 0)
        [parse_attr(args, line)]

      _ ->
        []
    end
  end

  defp parse_attr_options(keyword_list) do
    Enum.reduce(keyword_list, %{}, fn item, acc ->
      case item do
        {:required, value} -> Map.put(acc, :required, value)
        {:default, value} -> Map.put(acc, :default, inspect(value))
        {:values, {:__block__, _, values}} -> Map.put(acc, :values, Enum.map(values, &atom_to_name/1))
        {:values, values} when is_list(values) -> Map.put(acc, :values, Enum.map(values, &atom_to_name/1))
        {:doc, doc} when is_binary(doc) -> Map.put(acc, :doc, doc)
        _ -> acc
      end
    end)
  end

  defp parse_slot_options(keyword_list) do
    Enum.reduce(keyword_list, %{}, fn item, acc ->
      case item do
        {:required, value} -> Map.put(acc, :required, value)
        {:doc, doc} when is_binary(doc) -> Map.put(acc, :doc, doc)
        _ -> acc
      end
    end)
  end

  defp module_alias_to_string({:__aliases__, _, parts}) do
    Enum.join(parts, ".")
  end

  defp module_alias_to_string(atom) when is_atom(atom) do
    to_string(atom)
  end

  defp module_alias_to_string(_), do: "Unknown"

  defp atom_to_name(atom) when is_atom(atom) do
    # Remove leading : from atom
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
    # Escape quotes and backslashes
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
    result = PhoenixPulse.ComponentParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.ComponentParser.to_json(%{
      error: true,
      message: "Usage: elixir component-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
