#!/usr/bin/env elixir

# Phoenix Pulse - Template Parser
# Parses Phoenix template modules (View/HTML) and extracts template metadata
# Returns JSON with module info, embed_templates patterns, and function templates

defmodule PhoenixPulse.TemplateParser do
  @moduledoc """
  Parses Phoenix template modules and extracts template metadata.
  Uses Elixir's Code.string_to_quoted!/1 for accurate AST parsing.
  """

  def parse_file(file_path) do
    try do
      content = File.read!(file_path)
      {:ok, ast} = Code.string_to_quoted(content, columns: true, token_metadata: true)

      metadata = %{
        module: nil,
        embed_templates: [],
        module_type: nil,  # :view, :html, or nil
        function_templates: [],
        file_path: file_path
      }

      result = extract_template_info(ast, metadata)

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

  # Extract template info by walking the AST
  defp extract_template_info({:defmodule, _meta, [module_name, [do: block]]}, metadata) do
    module = module_to_string(module_name)
    new_metadata = %{metadata | module: module}
    process_module_body(block, new_metadata)
  end

  defp extract_template_info(_node, metadata) do
    metadata
  end

  # Process module body (list of statements)
  defp process_module_body({:__block__, _, statements}, metadata) do
    Enum.reduce(statements, metadata, fn statement, acc ->
      process_statement(statement, acc)
    end)
  end

  defp process_module_body(statement, metadata) do
    process_statement(statement, metadata)
  end

  # Process individual statements
  # Look for: use ..., :view or use ..., :html
  defp process_statement({:use, _meta, [_module, :view]}, metadata) do
    %{metadata | module_type: :view}
  end

  defp process_statement({:use, _meta, [_module, :html]}, metadata) do
    %{metadata | module_type: :html}
  end

  # Look for: embed_templates "pattern/*"
  defp process_statement({:embed_templates, _meta, args}, metadata) do
    case args do
      [pattern] when is_binary(pattern) ->
        %{metadata | embed_templates: [pattern | metadata.embed_templates]}

      _ ->
        metadata
    end
  end

  # Look for: def template_name(assigns) do
  defp process_statement({:def, meta, [signature, [do: _body]]}, metadata) do
    case extract_template_function(signature, meta) do
      {:ok, template_info} ->
        %{metadata | function_templates: [template_info | metadata.function_templates]}

      :skip ->
        metadata
    end
  end

  # Ignore other statements
  defp process_statement(_node, metadata) do
    metadata
  end

  # Extract template function info from function signature
  # Pattern: def template_name(assigns) do
  defp extract_template_function({name, _meta, args}, line_meta) when is_atom(name) do
    name_str = to_string(name)

    # Skip private functions (start with _)
    if String.starts_with?(name_str, "_") do
      :skip
    else
      # Check if function signature is: (assigns) or (assigns, _) etc.
      if matches_template_signature?(args) do
        line = Keyword.get(line_meta, :line, 0)

        {:ok, %{
          name: name_str,
          line: line,
          format: "html"  # Default format for function templates
        }}
      else
        :skip
      end
    end
  end

  defp extract_template_function(_signature, _meta) do
    :skip
  end

  # Check if function args match template signature: (assigns) or (assigns, ...)
  defp matches_template_signature?(args) when is_list(args) do
    case args do
      # def name(assigns) do
      [{:assigns, _, _}] ->
        true

      # def name(assigns, _other) do
      [{:assigns, _, _} | _rest] ->
        true

      _ ->
        false
    end
  end

  defp matches_template_signature?(_), do: false

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
    result = PhoenixPulse.TemplateParser.parse_file(file_path)
    IO.puts(result)

  _ ->
    error = PhoenixPulse.TemplateParser.to_json(%{
      error: true,
      message: "Usage: elixir template-parser.exs <file_path>"
    })
    IO.puts(error)
    System.halt(1)
end
