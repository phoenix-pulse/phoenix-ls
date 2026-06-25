defmodule PhoenixLS.Features.Completion.LiveView do
  @moduledoc """
  Completion items for LiveView assigns and events.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.{Facts, TemplateFacts}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: "@" <> assign_prefix}, facts) do
    facts
    |> Facts.by_kind(:assign)
    |> Enum.map(&assign_item/1)
    |> prefixed_items("@" <> assign_prefix)
  end

  def complete(
        %CursorContext{kind: :attribute_value, attribute: "phx-hook"},
        _facts
      ),
      do: []

  def complete(
        %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
        facts
      ) do
    facts
    |> Facts.by_kind(:live_event)
    |> Enum.map(&event_item/1)
    |> prefixed_items(prefix)
  end

  def complete(_context, _facts), do: []

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    with uri when is_binary(uri) <- uri,
         {:ok, context} <- CursorContext.at(source, position),
         items when is_list(items) <- complete(uri, source, position, context, facts) do
      items
    else
      _not_scoped_context -> []
    end
  end

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), CursorContext.t(), [
          Fact.t()
        ]) :: [CompletionItem.t()]
  def complete(uri, _source, position, %CursorContext{} = context, facts)
      when (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    with uri when is_binary(uri) <- uri do
      case TemplateFacts.module_for_uri(facts, uri) do
        {:ok, module} -> complete_source_context(context, facts, module)
        :error -> complete_component_source_context(uri, position, context, facts)
      end
    else
      _not_scoped_context -> []
    end
  end

  defp complete_source_context(
         %CursorContext{kind: :expression, prefix: "@" <> prefix},
         facts,
         module
       ) do
    facts
    |> Facts.by_kind(:assign)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.map(&assign_item/1)
    |> prefixed_items("@" <> prefix)
  end

  defp complete_source_context(
         %CursorContext{kind: :attribute_value, attribute: "phx-hook"},
         _facts,
         _module
       ),
       do: []

  defp complete_source_context(
         %CursorContext{kind: :attribute_value, attribute: "phx-" <> _event, prefix: prefix},
         facts,
         module
       ) do
    facts
    |> Facts.by_kind(:live_event)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.map(&event_item/1)
    |> prefixed_items(prefix)
  end

  defp complete_source_context(_context, _facts, _module), do: []

  defp complete_component_source_context(
         uri,
         position,
         %CursorContext{kind: :expression, prefix: "@" <> prefix},
         facts
       ) do
    with %Fact{} = component <- enclosing_component(uri, position, facts) do
      facts
      |> component_assign_facts(component.id)
      |> Enum.map(&component_assign_item/1)
      |> prefixed_items("@" <> prefix)
    else
      _no_component -> []
    end
  end

  defp complete_component_source_context(_uri, _position, _context, _facts), do: []

  defp enclosing_component(uri, position, facts) do
    facts
    |> Facts.by_kind(:component)
    |> Enum.filter(&(&1.uri == uri and contains_position?(&1.range, position)))
    |> Enum.sort_by(&range_size/1)
    |> List.first()
  end

  defp component_assign_facts(facts, component_id) do
    attrs =
      facts
      |> Facts.by_kind(:component_attr)
      |> Enum.filter(&(&1.data.component == component_id))

    slots =
      facts
      |> Facts.by_kind(:component_slot)
      |> Enum.filter(&(&1.data.component == component_id))

    attrs ++ slots
  end

  defp component_assign_item(%Fact{} = fact) do
    label = "@" <> fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.variable(),
       detail: "assign #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => component_assign_kind(fact.kind), "id" => fact.id}
     }}
  end

  defp component_assign_kind(:component_attr), do: "component_attr"
  defp component_assign_kind(:component_slot), do: "component_slot"

  defp contains_position?(%{start: start, end: finish}, position) do
    compare_position(start, position) != :gt and compare_position(position, finish) == :lt
  end

  defp range_size(%Fact{range: %{start: start, end: finish}}) do
    {finish.line - start.line, finish.character - start.character}
  end

  defp assign_item(fact) do
    label = "@" <> fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.variable(),
       detail: "assign #{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "assign", "id" => fact.id}
     }}
  end

  defp event_item(fact) do
    label = fact.data.event

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.event(),
       detail: "handle_event(\"#{label}\", ...)",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "live_event", "id" => fact.id}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp compare_position(%{line: left_line}, %{line: right_line}) when left_line < right_line,
    do: :lt

  defp compare_position(%{line: left_line}, %{line: right_line}) when left_line > right_line,
    do: :gt

  defp compare_position(%{character: left_character}, %{character: right_character})
       when left_character < right_character,
       do: :lt

  defp compare_position(%{character: left_character}, %{character: right_character})
       when left_character > right_character,
       do: :gt

  defp compare_position(_left, _right), do: :eq
end
