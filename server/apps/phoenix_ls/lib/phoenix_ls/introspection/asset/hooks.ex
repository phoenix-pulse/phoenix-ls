defmodule PhoenixLS.Introspection.Asset.Hooks do
  @moduledoc """
  Extracts source-ranged LiveView JavaScript hook definition facts.

  This is intentionally a small JavaScript-only scanner for tested hook-map
  assignment shapes. It must not be reused for Elixir, Phoenix, or HEEx
  semantics.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks
  alias PhoenixLS.Support.Positions

  @spec facts(String.t(), String.t(), map()) :: [Fact.t()]
  def facts(uri, source, provenance)
      when is_binary(uri) and is_binary(source) and is_map(provenance) do
    source
    |> code_segments()
    |> Enum.flat_map(&segment_facts(&1, uri, source, provenance))
  end

  defp hook_id(uri, name), do: "#{uri}:hook:#{name}"

  defp segment_facts({segment_start, segment_source}, uri, source, provenance) do
    segment_source
    |> hook_map_assignments()
    |> Enum.map(fn {relative_offset, name} ->
      start_offset = segment_start + relative_offset
      length = byte_size(name)
      range = range!(source, start_offset, start_offset + length)

      Fact.new!(
        kind: :hook,
        id: hook_id(uri, name),
        uri: uri,
        range: range,
        provenance: Map.put(provenance, :scanner, :live_view_hook_map),
        data: %Hooks.Hook{name: name, source: :javascript_hook_map}
      )
    end)
  end

  defp hook_map_assignments(source) do
    scan_hook_lines(source, 0, [])
  end

  defp scan_hook_lines(source, line_start, matches) when line_start >= byte_size(source) do
    Enum.reverse(matches)
  end

  defp scan_hook_lines(source, line_start, matches) do
    line_end = next_newline(source, line_start)
    line = binary_part(source, line_start, line_end - line_start)

    matches =
      case hook_map_assignment(line) do
        {:ok, name_offset, name} -> [{line_start + name_offset, name} | matches]
        :error -> matches
      end

    next_line_start =
      if line_end < byte_size(source) do
        line_end + 1
      else
        line_end
      end

    scan_hook_lines(source, next_line_start, matches)
  end

  defp hook_map_assignment(line) do
    with hooks_offset <- skip_horizontal_whitespace(line, 0),
         true <- starts_at?(line, hooks_offset, "Hooks."),
         name_offset <- hooks_offset + byte_size("Hooks."),
         {:ok, name, after_name} <- take_js_identifier(line, name_offset),
         equals_offset <- skip_horizontal_whitespace(line, after_name),
         true <- byte_at(line, equals_offset) == "=",
         object_offset <- skip_horizontal_whitespace(line, equals_offset + 1),
         true <- byte_at(line, object_offset) == "{" do
      {:ok, name_offset, name}
    else
      _not_hook_assignment -> :error
    end
  end

  defp next_newline(source, offset) when offset >= byte_size(source), do: offset

  defp next_newline(source, offset) do
    if byte_at(source, offset) == "\n" do
      offset
    else
      next_newline(source, offset + 1)
    end
  end

  defp skip_horizontal_whitespace(source, offset) do
    case byte_at(source, offset) do
      " " -> skip_horizontal_whitespace(source, offset + 1)
      "\t" -> skip_horizontal_whitespace(source, offset + 1)
      _other -> offset
    end
  end

  defp take_js_identifier(source, offset) do
    if js_identifier_start?(source, offset) do
      end_offset = js_identifier_end(source, offset + 1)
      {:ok, binary_part(source, offset, end_offset - offset), end_offset}
    else
      :error
    end
  end

  defp js_identifier_end(source, offset) when offset >= byte_size(source), do: offset

  defp js_identifier_end(source, offset) do
    if js_identifier_part?(source, offset) do
      js_identifier_end(source, offset + 1)
    else
      offset
    end
  end

  defp js_identifier_start?(source, offset) do
    case char_at(source, offset) do
      char when char in ?A..?Z -> true
      char when char in ?a..?z -> true
      ?_ -> true
      ?$ -> true
      _other -> false
    end
  end

  defp js_identifier_part?(source, offset) do
    case char_at(source, offset) do
      char when char in ?A..?Z -> true
      char when char in ?a..?z -> true
      char when char in ?0..?9 -> true
      ?_ -> true
      ?$ -> true
      _other -> false
    end
  end

  defp code_segments(source) do
    source
    |> scan_code_segments(0, 0, [])
    |> Enum.reverse()
  end

  defp scan_code_segments(source, offset, code_start, segments)
       when offset >= byte_size(source) do
    add_segment(source, code_start, offset, segments)
  end

  defp scan_code_segments(source, offset, code_start, segments) do
    cond do
      starts_at?(source, offset, "//") ->
        segments = add_segment(source, code_start, offset, segments)
        next_offset = skip_line_comment(source, offset + 2)
        scan_code_segments(source, next_offset, next_offset, segments)

      starts_at?(source, offset, "/*") ->
        segments = add_segment(source, code_start, offset, segments)
        next_offset = skip_block_comment(source, offset + 2)
        scan_code_segments(source, next_offset, next_offset, segments)

      byte_at(source, offset) in ["\"", "'"] ->
        segments = add_segment(source, code_start, offset, segments)
        next_offset = skip_quoted_literal(source, offset + 1, byte_at(source, offset))
        scan_code_segments(source, next_offset, next_offset, segments)

      byte_at(source, offset) == "`" ->
        segments = add_segment(source, code_start, offset, segments)
        next_offset = skip_template_literal(source, offset + 1)
        scan_code_segments(source, next_offset, next_offset, segments)

      true ->
        scan_code_segments(source, offset + 1, code_start, segments)
    end
  end

  defp add_segment(_source, start_offset, end_offset, segments) when start_offset >= end_offset,
    do: segments

  defp add_segment(source, start_offset, end_offset, segments) do
    [{start_offset, binary_part(source, start_offset, end_offset - start_offset)} | segments]
  end

  defp skip_line_comment(source, offset) when offset >= byte_size(source), do: offset

  defp skip_line_comment(source, offset) do
    if byte_at(source, offset) == "\n" do
      offset + 1
    else
      skip_line_comment(source, offset + 1)
    end
  end

  defp skip_block_comment(source, offset) when offset >= byte_size(source), do: offset

  defp skip_block_comment(source, offset) do
    if starts_at?(source, offset, "*/") do
      offset + 2
    else
      skip_block_comment(source, offset + 1)
    end
  end

  defp skip_quoted_literal(source, offset, _quote) when offset >= byte_size(source), do: offset

  defp skip_quoted_literal(source, offset, quote) do
    cond do
      byte_at(source, offset) == "\\" ->
        skip_quoted_literal(source, min(offset + 2, byte_size(source)), quote)

      byte_at(source, offset) == quote ->
        offset + 1

      true ->
        skip_quoted_literal(source, offset + 1, quote)
    end
  end

  defp skip_template_literal(source, offset) when offset >= byte_size(source), do: offset

  defp skip_template_literal(source, offset) do
    cond do
      byte_at(source, offset) == "\\" ->
        skip_template_literal(source, min(offset + 2, byte_size(source)))

      byte_at(source, offset) == "`" ->
        offset + 1

      true ->
        skip_template_literal(source, offset + 1)
    end
  end

  defp range!(source, start_offset, end_offset) do
    {:ok, start_position} = Positions.offset_to_lsp_position(source, start_offset)
    {:ok, end_position} = Positions.offset_to_lsp_position(source, end_offset)

    %Range{
      start: position(start_position),
      end: position(end_position)
    }
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end

  defp starts_at?(source, offset, prefix) do
    size = byte_size(prefix)

    offset + size <= byte_size(source) and binary_part(source, offset, size) == prefix
  end

  defp byte_at(source, offset) when offset >= 0 and offset < byte_size(source) do
    binary_part(source, offset, 1)
  end

  defp byte_at(_source, _offset), do: nil

  defp char_at(source, offset) when offset >= 0 and offset < byte_size(source) do
    :binary.at(source, offset)
  end

  defp char_at(_source, _offset), do: nil
end
