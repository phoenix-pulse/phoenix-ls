defmodule PhoenixLS.LiveView.JSCommands do
  @moduledoc """
  Canonical Phoenix.LiveView.JS command metadata.
  """

  @commands [
    %{
      name: "show",
      detail: "Show elements",
      snippet: ~s[show(to: "${1:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"transition", ~s["${1:fade-in}"]},
        {"time", "${1:200}"},
        {"display", ~s["${1:block}"]},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "hide",
      detail: "Hide elements",
      snippet: ~s[hide(to: "${1:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"transition", ~s["${1:fade-out}"]},
        {"time", "${1:200}"},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "toggle",
      detail: "Toggle element visibility",
      snippet: ~s[toggle(to: "${1:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"in", ~s["${1:fade-in}"]},
        {"out", ~s["${1:fade-out}"]},
        {"time", "${1:200}"},
        {"display", ~s["${1:block}"]},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "add_class",
      detail: "Add classes to elements",
      snippet: ~s[add_class("${1:class-name}", to: "${2:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"transition", ~s["${1:fade-in}"]},
        {"time", "${1:200}"},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "remove_class",
      detail: "Remove classes from elements",
      snippet: ~s[remove_class("${1:class-name}", to: "${2:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"transition", ~s["${1:fade-out}"]},
        {"time", "${1:200}"},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "toggle_class",
      detail: "Toggle classes on elements",
      snippet: ~s[toggle_class("${1:class-name}", to: "${2:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"transition", ~s["${1:fade}"]},
        {"time", "${1:200}"},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "set_attribute",
      detail: "Set an attribute on elements",
      snippet: ~s[set_attribute({"${1:attribute}", "${2:value}"}, to: "${3:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "remove_attribute",
      detail: "Remove an attribute from elements",
      snippet: ~s[remove_attribute("${1:attribute}", to: "${2:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "toggle_attribute",
      detail: "Toggle an attribute on elements",
      snippet:
        ~s[toggle_attribute({"${1:attribute}", "${2:true}", "${3:false}"}, to: "${4:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "ignore_attributes",
      detail: "Ignore attributes across LiveView patches",
      snippet: "ignore_attributes([\"${1:attribute}\"], to: \"${2:#selector}\")",
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "transition",
      detail: "Transition elements",
      snippet: ~s[transition("${1:transition}", to: "${2:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"time", "${1:200}"},
        {"blocking", "${1:true}"}
      ]
    },
    %{
      name: "focus",
      detail: "Focus a selector",
      snippet: ~s[focus(to: "${1:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "focus_first",
      detail: "Focus the first focusable child",
      snippet: ~s[focus_first(to: "${1:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "push_focus",
      detail: "Push focus for later restore",
      snippet: ~s[push_focus(to: "${1:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{name: "pop_focus", detail: "Restore pushed focus", snippet: "pop_focus()", options: []},
    %{
      name: "push",
      detail: "Push an event to the server",
      snippet: ~s[push("${1:event}"${2:, value: %{${3:key}: ${4:value}}})],
      options: [
        {"value", "%{${1:key}: ${2:value}}"},
        {"target", ~s["${1:#target}"]},
        {"loading", ~s["${1:#loading}"]},
        {"page_loading", "${1:true}"}
      ]
    },
    %{
      name: "navigate",
      detail: "Navigate through LiveView",
      snippet: ~s[navigate("${1:/path}")],
      options: [{"replace", "${1:false}"}]
    },
    %{
      name: "patch",
      detail: "Patch the current LiveView",
      snippet: ~s[patch("${1:/path}")],
      options: [{"replace", "${1:false}"}]
    },
    %{
      name: "dispatch",
      detail: "Dispatch a DOM event",
      snippet: ~s[dispatch("${1:event}", to: "${2:#selector}")],
      options: [
        {"to", ~s["${1:#selector}"]},
        {"detail", "%{${1:key}: ${2:value}}"},
        {"bubbles", "${1:true}"}
      ]
    },
    %{
      name: "exec",
      detail: "Execute JS commands from an element attribute",
      snippet: ~s[exec("${1:phx-remove}", to: "${2:#selector}")],
      options: [{"to", ~s["${1:#selector}"]}]
    },
    %{
      name: "concat",
      detail: "Combine two JS commands",
      snippet: "concat(${1:js1}, ${2:js2})",
      options: []
    }
  ]

  @spec commands() :: [map()]
  def commands, do: @commands

  @spec command(String.t()) :: map() | nil
  def command(name) when is_binary(name) do
    Enum.find(@commands, &(&1.name == name))
  end

  @spec command_for_prefix(String.t()) :: map() | nil
  def command_for_prefix(prefix) when is_binary(prefix) do
    prefix
    |> command_name_prefix()
    |> unique_command_with_prefix()
  end

  @spec names() :: [String.t()]
  def names do
    @commands
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  @spec options(String.t()) :: [{String.t(), String.t()}]
  def options(command_name) when is_binary(command_name) do
    case command(command_name) do
      %{options: options} -> options
      nil -> []
    end
  end

  @spec option_names(String.t()) :: [String.t()]
  def option_names(command_name) do
    command_name
    |> options()
    |> Enum.map(fn {name, _snippet} -> name end)
  end

  @spec markdown(map()) :: String.t()
  def markdown(%{name: name, detail: detail, options: options, snippet: snippet}) do
    [
      "```elixir\nPhoenix.LiveView.JS.#{name}\n```",
      detail,
      options_line(options),
      "Example: `JS.#{snippet_example(snippet)}`"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  @spec signature_label(map()) :: String.t()
  def signature_label(%{name: name, options: options}) do
    "JS.#{name}(#{options |> Enum.map_join(", ", fn {option, _snippet} -> option end)})"
  end

  @spec invalid_options(term()) :: [
          %{command: String.t(), option: String.t(), known_options: [String.t()]}
        ]
  def invalid_options(ast) do
    ast
    |> nodes()
    |> Enum.flat_map(&invalid_options_from_node/1)
  end

  defp invalid_options_from_node(
         {{:., _meta, [{:__aliases__, _alias_meta, [:JS]}, command]}, _call_meta, args}
       )
       when is_atom(command) and is_list(args) do
    invalid_options_for_command(Atom.to_string(command), args)
  end

  defp invalid_options_from_node(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView, :JS]}, command]},
          _call_meta, args}
       )
       when is_atom(command) and is_list(args) do
    invalid_options_for_command(Atom.to_string(command), args)
  end

  defp invalid_options_from_node({command, _meta, args})
       when is_atom(command) and is_list(args) do
    command
    |> Atom.to_string()
    |> invalid_options_for_command(args)
  end

  defp invalid_options_from_node(_node), do: []

  defp invalid_options_for_command(command_name, args) do
    known_options = option_names(command_name)

    if known_options == [] do
      []
    else
      args
      |> Enum.flat_map(&keyword_option_names/1)
      |> Enum.reject(&(&1 in known_options))
      |> Enum.map(&%{command: command_name, option: &1, known_options: known_options})
    end
  end

  defp keyword_option_names(options) when is_list(options) do
    if Keyword.keyword?(options) do
      Enum.flat_map(options, fn
        {name, _value} when is_atom(name) -> [Atom.to_string(name)]
        _entry -> []
      end)
    else
      []
    end
  end

  defp keyword_option_names(_options), do: []

  defp nodes(ast) do
    {_ast, nodes} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, [node | acc]}
      end)

    Enum.reverse(nodes)
  end

  defp command_name_prefix(prefix) do
    prefix
    |> String.split("|>")
    |> List.last()
    |> String.trim_leading()
    |> trim_js_alias()
    |> leading_command_name()
  end

  defp trim_js_alias("JS." <> rest), do: rest
  defp trim_js_alias("Phoenix.LiveView.JS." <> rest), do: rest
  defp trim_js_alias(rest), do: rest

  defp leading_command_name(value) do
    value
    |> String.graphemes()
    |> Enum.take_while(&command_name_grapheme?/1)
    |> Enum.join()
  end

  defp command_name_grapheme?(grapheme) do
    grapheme not in ["", " ", "\t", "\n", "\r", "(", ")", ",", "{", "}"]
  end

  defp unique_command_with_prefix(""), do: nil

  defp unique_command_with_prefix(prefix) do
    case Enum.filter(@commands, &String.starts_with?(&1.name, prefix)) do
      [command] -> command
      _none_or_ambiguous -> command(prefix)
    end
  end

  defp options_line([]), do: nil

  defp options_line(options) do
    "Options: " <> Enum.map_join(options, ", ", fn {name, _snippet} -> name end)
  end

  defp snippet_example(snippet) do
    strip_snippet_placeholders(snippet)
  end

  defp strip_snippet_placeholders(snippet) do
    case String.split(snippet, "${", parts: 2) do
      [value] ->
        value

      [before, rest] ->
        case String.split(rest, "}", parts: 2) do
          [placeholder, remainder] ->
            before <> placeholder_value(placeholder) <> strip_snippet_placeholders(remainder)

          [_unterminated] ->
            snippet
        end
    end
  end

  defp placeholder_value(placeholder) do
    case String.split(placeholder, ":", parts: 2) do
      [_index, value] -> value
      [value] -> value
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
