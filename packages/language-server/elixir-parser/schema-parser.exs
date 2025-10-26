#!/usr/bin/env elixir

# Phoenix Pulse - Schema Parser
# Parses Ecto schemas using Elixir's AST
# Returns JSON with schema metadata (fields, associations, etc.)

defmodule PhoenixPulse.SchemaParser do
  @moduledoc """
  Parses Ecto schemas and extracts metadata.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        schemas: [],
        file_path: file_path,
        aliases: %{}
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

  # Parse alias declarations
  defp process_node({:alias, _meta, [{:__aliases__, _, parts}]} = node, acc) do
    full_name = Enum.join(parts, ".")
    short_name = List.last(parts) |> to_string()
    aliases = Map.put(acc.aliases, short_name, full_name)
    {node, %{acc | aliases: aliases}}
  end

  defp process_node({:alias, _meta, [{:__aliases__, _, parts}, [as: {:__aliases__, _, as_parts}]]} = node, acc) do
    full_name = Enum.join(parts, ".")
    short_name = Enum.join(as_parts, ".")
    aliases = Map.put(acc.aliases, short_name, full_name)
    {node, %{acc | aliases: aliases}}
  end

  # Parse schema block
  defp process_node({:schema, meta, [table_name, [do: block]]} = node, acc) when is_binary(table_name) do
    line = Keyword.get(meta, :line, 0)
    schema = parse_schema_block(block, acc.module, table_name, line, acc.aliases)
    {node, %{acc | schemas: [schema | acc.schemas]}}
  end

  # Parse embedded_schema block
  defp process_node({:embedded_schema, meta, [[do: block]]} = node, acc) do
    line = Keyword.get(meta, :line, 0)
    schema = parse_schema_block(block, acc.module, nil, line, acc.aliases)
    {node, %{acc | schemas: [schema | acc.schemas]}}
  end

  defp process_node(node, acc) do
    {node, acc}
  end

  defp parse_schema_block(block, module_name, table_name, line, aliases) do
    fields = []
    associations = []

    {fields, associations} = extract_schema_fields(block, fields, associations, module_name, aliases)

    # Auto-add id and timestamps if it's a regular schema
    fields = if table_name do
      # Add id if not present
      has_id = Enum.any?(fields, fn f -> f.name == "id" end)
      fields_with_id = if has_id, do: fields, else: [%{name: "id", type: "id", elixir_type: nil} | fields]

      # Check if timestamps() was called
      has_timestamps = Enum.any?(fields, fn f -> f.name == "inserted_at" or f.name == "updated_at" end)
      if has_timestamps do
        fields_with_id
      else
        # Timestamps might be added, we'll detect if we see the timestamps() call
        fields_with_id
      end
    else
      fields
    end

    %{
      module_name: module_name,
      table_name: table_name,
      line: line,
      fields: Enum.reverse(fields),
      associations: Enum.reverse(associations)
    }
  end

  defp extract_schema_fields({:__block__, _, statements}, fields, associations, module_name, aliases) do
    Enum.reduce(statements, {fields, associations}, fn statement, {f_acc, a_acc} ->
      extract_field_from_statement(statement, f_acc, a_acc, module_name, aliases)
    end)
  end

  defp extract_schema_fields(statement, fields, associations, module_name, aliases) do
    extract_field_from_statement(statement, fields, associations, module_name, aliases)
  end

  defp extract_field_from_statement({:field, _, [field_atom, type_atom | _]}, fields, associations, _module_name, _aliases) when is_atom(field_atom) and is_atom(type_atom) do
    field = %{
      name: atom_to_name(field_atom),
      type: atom_to_name(type_atom),
      elixir_type: nil
    }
    {[field | fields], associations}
  end

  # belongs_to :user, User
  defp extract_field_from_statement({:belongs_to, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    full_type = resolve_type(type_name, module_name, aliases)

    field = %{
      name: field_name,
      type: "assoc",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "belongs_to"
    }

    {[field | fields], [association | associations]}
  end

  # has_one :profile, Profile
  defp extract_field_from_statement({:has_one, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    full_type = resolve_type(type_name, module_name, aliases)

    field = %{
      name: field_name,
      type: "assoc",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "has_one"
    }

    {[field | fields], [association | associations]}
  end

  # has_many :posts, Post
  defp extract_field_from_statement({:has_many, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    full_type = resolve_type(type_name, module_name, aliases)

    field = %{
      name: field_name,
      type: "list",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "has_many"
    }

    {[field | fields], [association | associations]}
  end

  # many_to_many :tags, Tag
  defp extract_field_from_statement({:many_to_many, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    full_type = resolve_type(type_name, module_name, aliases)

    field = %{
      name: field_name,
      type: "list",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "many_to_many"
    }

    {[field | fields], [association | associations]}
  end

  # embeds_one :address, Address
  defp extract_field_from_statement({:embeds_one, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, _aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    # Embeds default to current module namespace
    full_type = "#{module_name}.#{type_name}"

    field = %{
      name: field_name,
      type: "embed",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "embeds_one"
    }

    {[field | fields], [association | associations]}
  end

  # embeds_many :addresses, Address
  defp extract_field_from_statement({:embeds_many, _, [field_atom, {:__aliases__, _, type_parts} | _]}, fields, associations, module_name, _aliases) when is_atom(field_atom) do
    field_name = atom_to_name(field_atom)
    type_name = Enum.join(type_parts, ".")
    full_type = "#{module_name}.#{type_name}"

    field = %{
      name: field_name,
      type: "list",
      elixir_type: full_type
    }

    association = %{
      field_name: field_name,
      target_module: full_type,
      type: "embeds_many"
    }

    {[field | fields], [association | associations]}
  end

  # timestamps()
  defp extract_field_from_statement({:timestamps, _, _}, fields, associations, _module_name, _aliases) do
    inserted_at = %{name: "inserted_at", type: "naive_datetime", elixir_type: nil}
    updated_at = %{name: "updated_at", type: "naive_datetime", elixir_type: nil}
    {[updated_at, inserted_at | fields], associations}
  end

  defp extract_field_from_statement(_statement, fields, associations, _module_name, _aliases) do
    {fields, associations}
  end

  # Resolve type with aliases
  defp resolve_type(type_name, module_name, aliases) do
    cond do
      # Already a full path (contains dots)
      String.contains?(type_name, ".") ->
        type_name

      # Check aliases
      Map.has_key?(aliases, type_name) ->
        Map.get(aliases, type_name)

      # Fall back to same namespace
      true ->
        parts = String.split(module_name, ".")
        namespace = parts
          |> Enum.take(length(parts) - 1)
          |> Enum.join(".")

        if namespace != "" do
          "#{namespace}.#{type_name}"
        else
          type_name
        end
    end
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
    result = PhoenixPulse.SchemaParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.SchemaParser.to_json(%{
      error: true,
      message: "Usage: elixir schema-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
