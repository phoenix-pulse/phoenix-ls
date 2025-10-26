#!/usr/bin/env elixir

# Install Jason for JSON encoding
Mix.install([{:jason, "~> 1.4"}], verbose: false)

# HEEx Template Parser for Phoenix Pulse
#
# Parses HEEx templates to extract component usages, slots, and nesting structure.
# Returns JSON for consumption by TypeScript layer.
#
# Usage:
#   elixir heex-parser.exs <file_path>
#   elixir heex-parser.exs --stdin < file.heex

defmodule HEExParser do
  @moduledoc """
  Parses HEEx templates to extract component structure.

  Unlike other parsers, this doesn't use Elixir's AST because HEEx is markup, not code.
  Instead, we use systematic string parsing to extract component usages.

  This is more maintainable than regex in TypeScript because:
  - Can be tested independently
  - Can be enhanced without touching TypeScript
  - Can leverage Elixir's powerful string/regex functions
  - Consistent with architecture of other parsers
  """

  defmodule ComponentUsage do
    @enforce_keys [:name, :start_offset, :end_offset, :name_start, :name_end]
    defstruct [
      :name,
      :module_context,
      :is_local,
      :start_offset,
      :end_offset,
      :name_start,
      :name_end,
      :self_closing,
      :attributes,
      :slots,
      :parent_component
    ]
  end

  defmodule SlotUsage do
    @enforce_keys [:name, :start_offset, :end_offset]
    defstruct [:name, :start_offset, :end_offset, :self_closing, :attributes]
  end


  def parse_file(path) do
    content = File.read!(path)
    parse_content(content, path)
  end

  def parse_stdin do
    content = IO.read(:stdio, :all)
    parse_content(content, "stdin")
  end

  def parse_content(content, source \\ "unknown") do
    # Find all component usages
    local_components = find_local_components(content)
    remote_components = find_remote_components(content)
    all_components = Enum.sort_by(local_components ++ remote_components, & &1.start_offset)

    # Build nesting structure
    components_with_nesting = build_nesting_structure(all_components)

    # Find slots within each component
    components_with_slots = Enum.map(components_with_nesting, fn component ->
      slots = find_slots_in_component(content, component)
      %{component | slots: slots}
    end)

    %{
      source: source,
      components: components_with_slots,
      success: true
    }
  rescue
    e ->
      %{
        source: source,
        error: Exception.message(e),
        success: false
      }
  end

  # Find all local components: <.name ...>
  defp find_local_components(content) do
    # Pattern: <.component_name (with word boundary)
    Regex.scan(~r/<\.([a-z_][a-z0-9_]*)\b/i, content, return: :index)
    |> Enum.map(fn [{match_start, _match_length}, {name_start, name_length}] ->
      # Use binary.part for byte-based slicing (Regex.scan returns byte offsets)
      name = :binary.part(content, name_start, name_length)

      # Find full component boundaries (opening tag to closing tag or />)
      {self_closing, end_offset} = find_component_end(content, match_start, name)

      %ComponentUsage{
        name: name,
        module_context: nil,
        is_local: true,
        start_offset: match_start,
        end_offset: end_offset,
        name_start: name_start,
        name_end: name_start + name_length,
        self_closing: self_closing,
        attributes: [],
        slots: [],
        parent_component: nil
      }
    end)
  end

  # Find all remote components: <Module.name ...>
  defp find_remote_components(content) do
    # Pattern: <ModuleName.component_name (with word boundary)
    Regex.scan(~r/<([A-Z][\w]*(?:\.[A-Z][\w]*)*)\.([a-z_][a-z0-9_]*)\b/i, content, return: :index)
    |> Enum.map(fn [{match_start, _}, {module_start, module_length}, {name_start, name_length}] ->
      # Use binary.part for byte-based slicing (Regex.scan returns byte offsets)
      module_context = :binary.part(content, module_start, module_length)
      name = :binary.part(content, name_start, name_length)

      {self_closing, end_offset} = find_component_end(content, match_start, name)

      %ComponentUsage{
        name: name,
        module_context: module_context,
        is_local: false,
        start_offset: match_start,
        end_offset: end_offset,
        name_start: name_start,
        name_end: name_start + name_length,
        self_closing: self_closing,
        attributes: [],
        slots: [],
        parent_component: nil
      }
    end)
  end

  # Find where a component ends (either /> or </name>)
  defp find_component_end(content, start_offset, component_name) do
    # Find the opening tag's closing >
    opening_tag_end = find_tag_closing_bracket(content, start_offset)

    if opening_tag_end == -1 do
      {false, start_offset + 50}  # Fallback
    else
      # Check if self-closing (use binary.part for byte-based slicing)
      before_start = max(0, opening_tag_end - 10)
      before_length = min(10, opening_tag_end - before_start)
      before_bracket = :binary.part(content, before_start, before_length)
      if String.contains?(before_bracket, "/") do
        # Self-closing: <.name />
        {true, opening_tag_end + 1}
      else
        # Find matching closing tag: </.name>
        closing_tag_pattern = ~r/<\/\.?#{Regex.escape(component_name)}>/
        # Use binary.part to slice from opening_tag_end to end
        remaining = :binary.part(content, opening_tag_end, byte_size(content) - opening_tag_end)
        case Regex.run(closing_tag_pattern, remaining, return: :index) do
          [{rel_start, length} | _] ->
            abs_start = opening_tag_end + rel_start
            {false, abs_start + length}

          nil ->
            # No closing tag found, treat as self-closing
            {true, opening_tag_end + 1}
        end
      end
    end
  end

  # Find the > that closes a tag, accounting for nested braces
  defp find_tag_closing_bracket(content, start_offset) do
    length = String.length(content)
    find_bracket_helper(content, start_offset, length, 0, false, false)
  end

  defp find_bracket_helper(content, idx, length, brace_depth, in_string, in_attr) when idx < length do
    char = String.at(content, idx)

    cond do
      # Handle string boundaries
      char == "\"" and not in_string ->
        find_bracket_helper(content, idx + 1, length, brace_depth, true, in_attr)

      char == "\"" and in_string ->
        find_bracket_helper(content, idx + 1, length, brace_depth, false, in_attr)

      # Skip everything inside strings
      in_string ->
        find_bracket_helper(content, idx + 1, length, brace_depth, in_string, in_attr)

      # Track brace depth for expressions like {if @foo, do: "bar"}
      char == "{" ->
        find_bracket_helper(content, idx + 1, length, brace_depth + 1, in_string, true)

      char == "}" ->
        find_bracket_helper(content, idx + 1, length, max(0, brace_depth - 1), in_string, in_attr)

      # Found the closing > and we're not inside braces
      char == ">" and brace_depth == 0 ->
        idx

      # Keep searching
      true ->
        find_bracket_helper(content, idx + 1, length, brace_depth, in_string, in_attr)
    end
  end

  defp find_bracket_helper(_content, idx, _length, _brace_depth, _in_string, _in_attr), do: idx

  # Build parent-child nesting relationships
  defp build_nesting_structure(components) do
    Enum.map(components, fn component ->
      # Find parent: component that contains this one
      parent = Enum.find(components, fn potential_parent ->
        potential_parent.start_offset < component.start_offset and
        component.end_offset <= potential_parent.end_offset and
        potential_parent != component
      end)

      %{component | parent_component: parent && parent.name}
    end)
  end

  # Find slots within a component's content
  defp find_slots_in_component(content, component) do
    if component.self_closing do
      []
    else
      # Extract component content (between opening and closing tags)
      opening_end = find_tag_closing_bracket(content, component.start_offset)
      if opening_end == -1 or opening_end >= component.end_offset do
        []
      else
        # Use binary.part for byte-based slicing
        slice_start = opening_end + 1
        slice_length = component.end_offset - slice_start
        content_slice = :binary.part(content, slice_start, slice_length)
        find_slots(content_slice, opening_end + 1)
      end
    end
  end

  # Find all slots: <:slot_name ...>
  defp find_slots(content, base_offset) do
    Regex.scan(~r/<:([a-z_][a-z0-9_-]*)\b/i, content, return: :index)
    |> Enum.map(fn [{match_start, _match_length}, {name_start, name_length}] ->
      # Use binary.part for byte-based slicing (Regex.scan returns byte offsets)
      name = :binary.part(content, name_start, name_length)

      # Find slot end (either /> or </:name>)
      {self_closing, end_offset} = find_slot_end(content, match_start, name)

      %SlotUsage{
        name: name,
        start_offset: base_offset + match_start,
        end_offset: base_offset + end_offset,
        self_closing: self_closing,
        attributes: []
      }
    end)
  end

  # Find where a slot ends
  defp find_slot_end(content, start_offset, slot_name) do
    opening_tag_end = find_tag_closing_bracket(content, start_offset)

    if opening_tag_end == -1 do
      {false, start_offset + 20}
    else
      # Use binary.part for byte-based slicing
      before_start = max(0, opening_tag_end - 5)
      before_length = min(5, opening_tag_end - before_start)
      before_bracket = :binary.part(content, before_start, before_length)
      if String.contains?(before_bracket, "/") do
        {true, opening_tag_end + 1}
      else
        # Find </:slot_name>
        closing_pattern = ~r/<\/:#{Regex.escape(slot_name)}>/
        # Use binary.part to slice from opening_tag_end to end
        remaining = :binary.part(content, opening_tag_end, byte_size(content) - opening_tag_end)
        case Regex.run(closing_pattern, remaining, return: :index) do
          [{rel_start, length} | _] ->
            {false, opening_tag_end + rel_start + length}
          nil ->
            {true, opening_tag_end + 1}
        end
      end
    end
  end

  def to_json(result) do
    # Manually convert structs to maps for JSON encoding
    converted = %{
      source: result.source,
      success: result.success,
      components: if(result[:components], do: Enum.map(result.components, &component_to_map/1), else: nil),
      error: result[:error]
    }
    Jason.encode!(converted, pretty: false)
  end

  # Convert ComponentUsage struct to plain map
  defp component_to_map(component) do
    %{
      name: component.name,
      module_context: component.module_context,
      is_local: component.is_local,
      start_offset: component.start_offset,
      end_offset: component.end_offset,
      name_start: component.name_start,
      name_end: component.name_end,
      self_closing: component.self_closing,
      attributes: component.attributes,
      slots: Enum.map(component.slots, &slot_to_map/1),
      parent_component: component.parent_component
    }
  end

  # Convert SlotUsage struct to plain map
  defp slot_to_map(slot) do
    %{
      name: slot.name,
      start_offset: slot.start_offset,
      end_offset: slot.end_offset,
      self_closing: slot.self_closing,
      attributes: slot.attributes
    }
  end
end

# Main execution
case System.argv() do
  ["--stdin"] ->
    HEExParser.parse_stdin()
    |> HEExParser.to_json()
    |> IO.puts()

  [path] ->
    HEExParser.parse_file(path)
    |> HEExParser.to_json()
    |> IO.puts()

  _ ->
    IO.puts(:stderr, "Usage: elixir heex-parser.exs <file_path>")
    IO.puts(:stderr, "       elixir heex-parser.exs --stdin < file.heex")
    System.halt(1)
end
