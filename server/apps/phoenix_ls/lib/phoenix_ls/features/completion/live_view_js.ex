defmodule PhoenixLS.Features.Completion.LiveViewJS do
  @moduledoc """
  Completion items for Phoenix.LiveView.JS commands in `phx-*` bindings.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @commands [
    %{name: "show", detail: "Show elements", snippet: ~s[show(to: "${1:#selector}")]},
    %{name: "hide", detail: "Hide elements", snippet: ~s[hide(to: "${1:#selector}")]},
    %{
      name: "toggle",
      detail: "Toggle element visibility",
      snippet: ~s[toggle(to: "${1:#selector}")]
    },
    %{
      name: "add_class",
      detail: "Add classes to elements",
      snippet: ~s[add_class("${1:class-name}", to: "${2:#selector}")]
    },
    %{
      name: "remove_class",
      detail: "Remove classes from elements",
      snippet: ~s[remove_class("${1:class-name}", to: "${2:#selector}")]
    },
    %{
      name: "toggle_class",
      detail: "Toggle classes on elements",
      snippet: ~s[toggle_class("${1:class-name}", to: "${2:#selector}")]
    },
    %{
      name: "set_attribute",
      detail: "Set an attribute on elements",
      snippet: ~s[set_attribute({"${1:attribute}", "${2:value}"}, to: "${3:#selector}")]
    },
    %{
      name: "remove_attribute",
      detail: "Remove an attribute from elements",
      snippet: ~s[remove_attribute("${1:attribute}", to: "${2:#selector}")]
    },
    %{
      name: "toggle_attribute",
      detail: "Toggle an attribute on elements",
      snippet:
        ~s[toggle_attribute({"${1:attribute}", "${2:true}", "${3:false}"}, to: "${4:#selector}")]
    },
    %{
      name: "ignore_attributes",
      detail: "Ignore attributes across LiveView patches",
      snippet: "ignore_attributes([\"${1:attribute}\"], to: \"${2:#selector}\")"
    },
    %{
      name: "transition",
      detail: "Transition elements",
      snippet: ~s[transition("${1:transition}", to: "${2:#selector}")]
    },
    %{name: "focus", detail: "Focus a selector", snippet: ~s[focus(to: "${1:#selector}")]},
    %{
      name: "focus_first",
      detail: "Focus the first focusable child",
      snippet: ~s[focus_first(to: "${1:#selector}")]
    },
    %{
      name: "push_focus",
      detail: "Push focus for later restore",
      snippet: ~s[push_focus(to: "${1:#selector}")]
    },
    %{name: "pop_focus", detail: "Restore pushed focus", snippet: "pop_focus()"},
    %{
      name: "push",
      detail: "Push an event to the server",
      snippet: ~s[push("${1:event}"${2:, value: %{${3:key}: ${4:value}}})]
    },
    %{
      name: "navigate",
      detail: "Navigate through LiveView",
      snippet: ~s[navigate("${1:/path}")]
    },
    %{name: "patch", detail: "Patch the current LiveView", snippet: ~s[patch("${1:/path}")]},
    %{
      name: "dispatch",
      detail: "Dispatch a DOM event",
      snippet: ~s[dispatch("${1:event}", to: "${2:#selector}")]
    },
    %{
      name: "exec",
      detail: "Execute JS commands from an element attribute",
      snippet: ~s[exec("${1:phx-remove}", to: "${2:#selector}")]
    }
  ]

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(
        %CursorContext{kind: :expression, attribute: "phx-" <> _binding, prefix: prefix},
        _facts
      ) do
    prefix = prefix || ""

    cond do
      pipe_chain_context?(prefix) ->
        pipe_command_prefix(prefix)
        |> command_items(:pipe)

      js_command_context?(prefix) ->
        js_command_prefix(prefix)
        |> command_items(:qualified)

      true ->
        []
    end
  end

  def complete(_context, _facts), do: []

  defp command_items(prefix, mode) do
    @commands
    |> Enum.map(&command_item(&1, mode))
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
