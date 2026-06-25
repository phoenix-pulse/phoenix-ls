defmodule PhoenixLS.Features.Diagnostics.Streams do
  @moduledoc """
  Diagnostics for HEEx `:for` tracking and LiveView stream usage.
  """

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}

  @spec diagnostics(Tag.t(), [Tag.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Tag{} = tag, tags) when is_list(tags) do
    for_tracking_diagnostics(tag) ++ stream_diagnostics(tag, tags)
  end

  defp for_tracking_diagnostics(%Tag{kind: :html} = tag) do
    case find_attr(tag, ":for") do
      %Attribute{} = for_attr ->
        if tracked_for?(tag) or stream_for?(for_attr) do
          []
        else
          item = for_item(for_attr)

          [
            Builder.diagnostic(
              for_attr.range,
              "phoenix.for_missing_key",
              ~s(HTML element "#{tag.name}" with :for should have DOM tracking. Add id={#{item}.id} or :key={#{item}.id}.),
              %{
                "kind" => "for_missing_key",
                "tag" => tag.name,
                "item" => item
              },
              DiagnosticSeverity.warning()
            )
          ]
        end

      nil ->
        []
    end
  end

  defp for_tracking_diagnostics(%Tag{}), do: []

  defp tracked_for?(%Tag{} = tag) do
    match?(%Attribute{}, find_attr(tag, "id")) or match?(%Attribute{}, find_attr(tag, ":key"))
  end

  defp stream_for?(%Attribute{value: value}) when is_binary(value) do
    String.contains?(value, "@streams.")
  end

  defp stream_for?(_attr), do: false

  defp stream_diagnostics(%Tag{} = tag, tags) do
    case find_attr(tag, ":for") do
      %Attribute{} = for_attr ->
        case stream_info(for_attr) do
          {:ok, stream} -> valid_stream_diagnostics(tag, tags, stream)
          {:invalid_pattern, stream} -> invalid_stream_pattern_diagnostic(for_attr, stream)
          :not_stream -> []
        end

      nil ->
        []
    end
  end

  defp valid_stream_diagnostics(%Tag{} = tag, tags, stream) do
    missing_stream_id_diagnostics(tag, stream) ++
      unnecessary_stream_key_diagnostics(tag, stream) ++
      missing_stream_update_diagnostics(tag, tags, stream)
  end

  defp invalid_stream_pattern_diagnostic(%Attribute{} = for_attr, stream) do
    [
      Builder.diagnostic(
        for_attr.range,
        "phoenix.stream_invalid_pattern",
        "Stream iteration must destructure tuple: use `{dom_id, #{stream.item}} <- @streams.#{stream.name}`.",
        %{
          "kind" => "stream_invalid_pattern",
          "stream" => stream.name,
          "item" => stream.item
        }
      )
    ]
  end

  defp missing_stream_id_diagnostics(%Tag{} = tag, stream) do
    if stream_id_attr?(tag, stream.dom_id) do
      []
    else
      [
        Builder.diagnostic(
          tag.name_range,
          "phoenix.stream_missing_id",
          "Stream item must have `id={#{stream.dom_id}}` for LiveView DOM tracking.",
          %{
            "kind" => "stream_missing_id",
            "stream" => stream.name,
            "dom_id" => stream.dom_id
          }
        )
      ]
    end
  end

  defp unnecessary_stream_key_diagnostics(%Tag{} = tag, stream) do
    case find_attr(tag, ":key") do
      %Attribute{} = key_attr ->
        [
          Builder.diagnostic(
            key_attr.range,
            "phoenix.stream_unnecessary_key",
            "Streams use `id={#{stream.dom_id}}` for DOM tracking, not `:key`.",
            %{
              "kind" => "stream_unnecessary_key",
              "stream" => stream.name,
              "dom_id" => stream.dom_id
            },
            DiagnosticSeverity.warning()
          )
        ]

      nil ->
        []
    end
  end

  defp missing_stream_update_diagnostics(%Tag{} = tag, tags, stream) do
    if stream_update_container?(tag, tags) do
      []
    else
      [
        Builder.diagnostic(
          tag.name_range,
          "phoenix.stream_missing_phx_update",
          ~s(Stream `@streams.#{stream.name}` should have `phx-update="stream"` on this element or an earlier container.),
          %{
            "kind" => "stream_missing_phx_update",
            "stream" => stream.name
          },
          DiagnosticSeverity.warning()
        )
      ]
    end
  end

  defp stream_info(%Attribute{value: value}) when is_binary(value) do
    with {:ok, {:for, _meta, clauses}} <- Code.string_to_quoted("for #{value}, do: nil"),
         {:<-, _generator_meta, [pattern, enumerable]} <- Enum.find(clauses, &generator?/1),
         {:ok, stream_name} <- stream_name(enumerable) do
      case stream_pattern(pattern) do
        {:ok, dom_id, item} ->
          {:ok, %{name: stream_name, dom_id: dom_id, item: item}}

        {:invalid, item} ->
          {:invalid_pattern, %{name: stream_name, item: item}}
      end
    else
      _not_stream -> :not_stream
    end
  end

  defp stream_info(_for_attr), do: :not_stream

  defp stream_name(
         {{:., _dot_meta, [{:@, _at_meta, [{:streams, _streams_meta, _context}]}, name]},
          _call_meta, []}
       )
       when is_atom(name) do
    {:ok, Atom.to_string(name)}
  end

  defp stream_name(_enumerable), do: :error

  defp stream_pattern({dom_id, item}) do
    with {:ok, dom_id_name} <- variable_name(dom_id),
         {:ok, item_name} <- variable_name(item) do
      {:ok, dom_id_name, item_name}
    else
      _invalid -> {:invalid, "item"}
    end
  end

  defp stream_pattern(pattern) do
    case variable_name(pattern) do
      {:ok, item_name} -> {:invalid, item_name}
      :error -> {:invalid, "item"}
    end
  end

  defp variable_name({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, Atom.to_string(name)}
  end

  defp variable_name(_ast), do: :error

  defp stream_id_attr?(%Tag{} = tag, dom_id) do
    case find_attr(tag, "id") do
      %Attribute{value: ^dom_id, value_kind: :expression} -> true
      _missing_or_static -> false
    end
  end

  defp stream_update_container?(%Tag{} = tag, tags) do
    phx_update_stream?(tag) or
      tags
      |> Enum.filter(&tag_before?(&1, tag))
      |> Enum.any?(&phx_update_stream?/1)
  end

  defp phx_update_stream?(%Tag{} = tag) do
    match?(%Attribute{value: "stream"}, find_attr(tag, "phx-update"))
  end

  defp tag_before?(%Tag{} = candidate, %Tag{} = tag) do
    before_position?(candidate.range.start, tag.range.start)
  end

  defp before_position?(%{line: left_line, character: left_char}, %{
         line: right_line,
         character: right_char
       }) do
    left_line < right_line or (left_line == right_line and left_char < right_char)
  end

  defp for_item(%Attribute{value: value}) when is_binary(value) do
    with {:ok, {:for, _meta, clauses}} <- Code.string_to_quoted("for #{value}, do: nil"),
         {:<-, _generator_meta, [pattern, _enumerable]} <- Enum.find(clauses, &generator?/1),
         {:ok, item} <- first_variable_name(pattern) do
      item
    else
      _unparseable -> "item"
    end
  end

  defp for_item(_attr), do: "item"

  defp generator?({:<-, _meta, [_pattern, _enumerable]}), do: true
  defp generator?(_clause), do: false

  defp first_variable_name(pattern) do
    {_ast, variable} =
      Macro.prewalk(pattern, nil, fn
        {name, _meta, context} = node, nil
        when is_atom(name) and (is_atom(context) or is_nil(context)) ->
          {node, Atom.to_string(name)}

        node, variable ->
          {node, variable}
      end)

    case variable do
      nil -> :error
      name -> {:ok, name}
    end
  end

  defp find_attr(%Tag{attrs: attrs}, name) do
    Enum.find(attrs, &(&1.name == name))
  end
end
