defmodule PhoenixLS.HEEx.Parser do
  @moduledoc """
  Small source-ranged HEEx parser for document-level features.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Support.Positions

  @spec parse(String.t()) :: {:ok, Document.t()} | {:error, atom()}
  def parse(source) when is_binary(source) do
    with {:ok, tags} <- scan(source, 0, []) do
      {:ok, %Document{tags: Enum.reverse(tags)}}
    end
  end

  defp scan(source, offset, tags) do
    case next_at(source, offset, "<") do
      :none ->
        {:ok, tags}

      {:ok, tag_start} ->
        cond do
          starts_at?(source, tag_start, "<%") ->
            scan(source, skip_heex_expression(source, tag_start), tags)

          starts_at?(source, tag_start, "</") ->
            with {:ok, tag_end} <- tag_end(source, tag_start + 2) do
              scan(source, tag_end + 1, tags)
            end

          starts_at?(source, tag_start, "<!") ->
            with {:ok, tag_end} <- tag_end(source, tag_start + 2) do
              scan(source, tag_end + 1, tags)
            end

          true ->
            with {:ok, tag, next_offset} <- parse_tag(source, tag_start) do
              scan(source, next_offset, [tag | tags])
            end
        end
    end
  end

  defp parse_tag(source, tag_start) do
    with {:ok, tag_end} <- tag_end(source, tag_start + 1),
         name_start <- skip_whitespace(source, tag_start + 1, tag_end),
         {:ok, name, name_end} <- parse_name(source, name_start, tag_end),
         {:ok, attrs} <- parse_attrs(source, name_end, tag_end, []),
         {:ok, range} <- range(source, tag_start, tag_end + 1),
         {:ok, name_range} <- range(source, name_start, name_end) do
      tag = %Tag{
        kind: tag_kind(name),
        name: name,
        range: range,
        name_range: name_range,
        attrs: attrs,
        self_closing?: self_closing?(source, tag_end)
      }

      {:ok, tag, tag_end + 1}
    end
  end

  defp parse_attrs(source, offset, tag_end, attrs) do
    offset = skip_whitespace(source, offset, tag_end)

    cond do
      offset >= tag_end ->
        {:ok, Enum.reverse(attrs)}

      byte_at(source, offset) == "/" ->
        {:ok, Enum.reverse(attrs)}

      true ->
        with {:ok, attr, next_offset} <- parse_attr(source, offset, tag_end) do
          parse_attrs(source, next_offset, tag_end, [attr | attrs])
        end
    end
  end

  defp parse_attr(source, name_start, tag_end) do
    with {:ok, name, name_end} <- parse_name(source, name_start, tag_end),
         value_start <- skip_whitespace(source, name_end, tag_end) do
      if byte_at(source, value_start) == "=" do
        parse_attr_value(
          source,
          name,
          name_start,
          name_end,
          skip_whitespace(source, value_start + 1, tag_end),
          tag_end
        )
      else
        boolean_attr(source, name, name_start, name_end)
      end
    end
  end

  defp parse_attr_value(source, name, name_start, name_end, value_start, tag_end) do
    case byte_at(source, value_start) do
      quote when quote in ["\"", "'"] ->
        with {:ok, value_end} <- scan_quoted_value(source, value_start + 1, quote, tag_end),
             {:ok, attr} <-
               valued_attr(
                 source,
                 name,
                 name_start,
                 name_end,
                 value_start + 1,
                 value_end,
                 :quoted,
                 value_end + 1
               ) do
          {:ok, attr, value_end + 1}
        end

      "{" ->
        with {:ok, value_end, next_offset} <-
               scan_expression_value(source, value_start + 1, tag_end),
             {:ok, attr} <-
               valued_attr(
                 source,
                 name,
                 name_start,
                 name_end,
                 value_start + 1,
                 value_end,
                 :expression,
                 next_offset
               ) do
          {:ok, attr, next_offset}
        end

      nil ->
        {:error, :unterminated_attr_value}

      _other ->
        value_end = scan_unquoted_value(source, value_start, tag_end)

        with {:ok, attr} <-
               valued_attr(
                 source,
                 name,
                 name_start,
                 name_end,
                 value_start,
                 value_end,
                 :unquoted,
                 value_end
               ) do
          {:ok, attr, value_end}
        end
    end
  end

  defp boolean_attr(source, name, name_start, name_end) do
    with {:ok, range} <- range(source, name_start, name_end),
         {:ok, name_range} <- range(source, name_start, name_end) do
      {:ok,
       %Attribute{
         name: name,
         range: range,
         name_range: name_range,
         value_kind: :boolean
       }, name_end}
    end
  end

  defp valued_attr(
         source,
         name,
         name_start,
         name_end,
         value_start,
         value_end,
         value_kind,
         attr_end
       ) do
    with {:ok, attr_range} <- range(source, name_start, attr_end),
         {:ok, name_range} <- range(source, name_start, name_end),
         {:ok, value_range} <- range(source, value_start, value_end) do
      {:ok,
       %Attribute{
         name: name,
         range: attr_range,
         name_range: name_range,
         value: source_slice(source, value_start, value_end),
         value_range: value_range,
         value_kind: value_kind
       }}
    end
  end

  defp tag_end(source, offset), do: scan_tag_end(source, offset, nil, 0)

  defp scan_tag_end(source, offset, _quote, _brace_depth) when offset >= byte_size(source) do
    {:error, :unterminated_tag}
  end

  defp scan_tag_end(source, offset, quote, brace_depth) do
    char = byte_at(source, offset)

    cond do
      is_binary(quote) and char == quote ->
        scan_tag_end(source, offset + 1, nil, brace_depth)

      is_binary(quote) ->
        scan_tag_end(source, offset + 1, quote, brace_depth)

      char in ["\"", "'"] ->
        scan_tag_end(source, offset + 1, char, brace_depth)

      char == "{" ->
        scan_tag_end(source, offset + 1, nil, brace_depth + 1)

      char == "}" and brace_depth > 0 ->
        scan_tag_end(source, offset + 1, nil, brace_depth - 1)

      char == ">" and brace_depth == 0 ->
        {:ok, offset}

      true ->
        scan_tag_end(source, offset + 1, nil, brace_depth)
    end
  end

  defp parse_name(source, offset, limit) do
    name_end = scan_name_end(source, offset, limit)

    if name_end > offset do
      {:ok, source_slice(source, offset, name_end), name_end}
    else
      {:error, :expected_name}
    end
  end

  defp scan_name_end(source, offset, limit) when offset < limit do
    char = byte_at(source, offset)

    if whitespace?(char) or char in ["=", "/", ">"] do
      offset
    else
      scan_name_end(source, offset + 1, limit)
    end
  end

  defp scan_name_end(_source, offset, _limit), do: offset

  defp scan_quoted_value(source, offset, quote, tag_end) when offset < tag_end do
    if byte_at(source, offset) == quote do
      {:ok, offset}
    else
      scan_quoted_value(source, offset + 1, quote, tag_end)
    end
  end

  defp scan_quoted_value(_source, _offset, _quote, _tag_end),
    do: {:error, :unterminated_attr_value}

  defp scan_expression_value(source, offset, tag_end) do
    scan_expression_value(source, offset, tag_end, nil, 1)
  end

  defp scan_expression_value(_source, offset, tag_end, _quote, _brace_depth)
       when offset >= tag_end do
    {:error, :unterminated_attr_value}
  end

  defp scan_expression_value(source, offset, tag_end, quote, brace_depth) do
    char = byte_at(source, offset)

    cond do
      is_binary(quote) and char == quote ->
        scan_expression_value(source, offset + 1, tag_end, nil, brace_depth)

      is_binary(quote) ->
        scan_expression_value(source, offset + 1, tag_end, quote, brace_depth)

      char in ["\"", "'"] ->
        scan_expression_value(source, offset + 1, tag_end, char, brace_depth)

      char == "{" ->
        scan_expression_value(source, offset + 1, tag_end, nil, brace_depth + 1)

      char == "}" and brace_depth == 1 ->
        {:ok, offset, offset + 1}

      char == "}" ->
        scan_expression_value(source, offset + 1, tag_end, nil, brace_depth - 1)

      true ->
        scan_expression_value(source, offset + 1, tag_end, nil, brace_depth)
    end
  end

  defp scan_unquoted_value(source, offset, tag_end) when offset < tag_end do
    char = byte_at(source, offset)

    if whitespace?(char) or char in ["/", ">"] do
      offset
    else
      scan_unquoted_value(source, offset + 1, tag_end)
    end
  end

  defp scan_unquoted_value(_source, offset, _tag_end), do: offset

  defp skip_heex_expression(source, tag_start) do
    case next_at(source, tag_start + 2, "%>") do
      {:ok, close_start} -> close_start + 2
      :none -> byte_size(source)
    end
  end

  defp skip_whitespace(source, offset, limit) when offset < limit do
    if whitespace?(byte_at(source, offset)) do
      skip_whitespace(source, offset + 1, limit)
    else
      offset
    end
  end

  defp skip_whitespace(_source, offset, _limit), do: offset

  defp self_closing?(source, tag_end) do
    case previous_non_whitespace(source, tag_end - 1) do
      {:ok, offset} -> byte_at(source, offset) == "/"
      :none -> false
    end
  end

  defp previous_non_whitespace(_source, offset) when offset < 0, do: :none

  defp previous_non_whitespace(source, offset) do
    if whitespace?(byte_at(source, offset)) do
      previous_non_whitespace(source, offset - 1)
    else
      {:ok, offset}
    end
  end

  defp tag_kind("." <> _name), do: :component
  defp tag_kind(":" <> _name), do: :slot
  defp tag_kind(name), do: if(String.contains?(name, "."), do: :remote_component, else: :html)

  defp range(source, start_offset, end_offset) do
    with {:ok, start_position} <- Positions.offset_to_lsp_position(source, start_offset),
         {:ok, end_position} <- Positions.offset_to_lsp_position(source, end_offset) do
      {:ok, %Range{start: position(start_position), end: position(end_position)}}
    end
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end

  defp next_at(source, offset, needle) when offset <= byte_size(source) do
    source
    |> binary_part(offset, byte_size(source) - offset)
    |> :binary.match(needle)
    |> case do
      {relative_offset, _length} -> {:ok, offset + relative_offset}
      :nomatch -> :none
    end
  end

  defp starts_at?(source, offset, prefix) do
    size = byte_size(prefix)

    offset + size <= byte_size(source) and binary_part(source, offset, size) == prefix
  end

  defp source_slice(source, start_offset, end_offset) do
    binary_part(source, start_offset, end_offset - start_offset)
  end

  defp byte_at(source, offset) when offset >= 0 and offset < byte_size(source) do
    binary_part(source, offset, 1)
  end

  defp byte_at(_source, _offset), do: nil

  defp whitespace?(char), do: char in [" ", "\t", "\n", "\r"]
end
