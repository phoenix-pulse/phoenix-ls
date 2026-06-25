defmodule PhoenixLS.Features.Completion.LiveViewJS do
  @moduledoc """
  Completion items for Phoenix.LiveView.JS commands in `phx-*` bindings.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.LiveView.Attributes
  alias PhoenixLS.LiveView.JSCommands

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(
        %CursorContext{kind: :expression, attribute: attribute, prefix: prefix},
        _facts
      )
      when is_binary(attribute) do
    prefix = prefix || ""

    if Attributes.js_command_attr?(attribute) do
      case option_context(prefix) do
        {:ok, command, option_prefix} ->
          option_items(command, option_prefix)

        :error ->
          command_completions(prefix)
      end
    else
      []
    end
  end

  def complete(_context, _facts), do: []

  defp command_completions(prefix) do
    cond do
      pipe_chain_context?(prefix) ->
        prefix
        |> pipe_command_prefix()
        |> command_items(:pipe)

      js_command_context?(prefix) ->
        prefix
        |> js_command_prefix()
        |> command_items(:qualified)

      empty_expression_context?(prefix) ->
        command_items("", :qualified)

      true ->
        []
    end
  end

  defp empty_expression_context?(prefix) do
    prefix
    |> String.trim_leading()
    |> Kernel.==("")
  end

  defp command_items(prefix, mode) do
    JSCommands.commands()
    |> Enum.map(&command_item(&1, mode))
    |> prefixed_items(prefix)
  end

  defp option_items(command, prefix) do
    command
    |> JSCommands.options()
    |> Enum.map(&option_item(command, &1))
    |> prefixed_items(prefix)
  end

  defp command_item(command, :qualified) do
    label = "JS." <> command.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.function(),
       detail: command.detail,
       insert_text: "JS." <> command.snippet,
       insert_text_format: InsertTextFormat.snippet(),
       data: command_data(command)
     }}
  end

  defp command_item(command, :pipe) do
    {command.name,
     %CompletionItem{
       label: command.name,
       kind: CompletionItemKind.function(),
       detail: command.detail,
       insert_text: command.snippet,
       insert_text_format: InsertTextFormat.snippet(),
       data: command_data(command)
     }}
  end

  defp option_item(command, {name, snippet}) do
    label = name <> ":"

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.property(),
       detail: "JS.#{command} option",
       insert_text: label <> " " <> snippet,
       insert_text_format: InsertTextFormat.snippet(),
       data: %{"kind" => "live_view_js_option", "command" => command, "name" => name}
     }}
  end

  defp option_context(prefix) do
    prefix = String.trim_leading(prefix)

    JSCommands.names()
    |> Enum.find_value(:error, &option_context_for_command(prefix, &1))
  end

  defp option_context_for_command(prefix, command) do
    qualified = option_tail(prefix, "JS." <> command <> "(")

    piped =
      option_tail(prefix, "|> " <> command <> "(") || option_tail(prefix, "|>" <> command <> "(")

    case qualified || piped do
      {:ok, tail} -> {:ok, command, option_prefix(tail)}
      nil -> nil
    end
  end

  defp option_tail(prefix, marker) do
    case String.split(prefix, marker) do
      [_single] ->
        nil

      parts ->
        tail = List.last(parts)

        if inside_open_call?(tail), do: {:ok, tail}, else: nil
    end
  end

  defp inside_open_call?(tail) do
    not String.contains?(tail, ")")
  end

  defp option_prefix(tail) do
    tail
    |> String.split(",")
    |> List.last()
    |> String.trim_leading()
  end

  defp js_command_context?(prefix) do
    prefix
    |> String.trim_leading()
    |> String.starts_with?("JS.")
  end

  defp js_command_prefix(prefix) do
    prefix
    |> String.trim_leading()
  end

  defp pipe_chain_context?(prefix) do
    prefix
    |> pipe_tail()
    |> case do
      :error -> false
      _tail -> true
    end
  end

  defp pipe_command_prefix(prefix) do
    prefix
    |> pipe_tail()
    |> case do
      {:ok, tail} -> String.trim_leading(tail)
      :error -> ""
    end
  end

  defp pipe_tail(prefix) do
    case String.split(prefix, "|>") do
      [_single] -> :error
      parts -> {:ok, List.last(parts)}
    end
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp command_data(command) do
    %{"kind" => "live_view_js_command", "name" => command.name}
  end
end
