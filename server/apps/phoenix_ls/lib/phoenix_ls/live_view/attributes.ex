defmodule PhoenixLS.LiveView.Attributes do
  @moduledoc """
  Canonical LiveView `phx-*` attribute metadata used by completions,
  diagnostics, and template indexing.
  """

  @event_attrs [
    "phx-click",
    "phx-submit",
    "phx-change",
    "phx-blur",
    "phx-focus",
    "phx-keydown",
    "phx-keyup",
    "phx-window-keydown",
    "phx-window-keyup",
    "phx-window-focus",
    "phx-window-blur",
    "phx-click-away",
    "phx-capture-click",
    "phx-viewport-top",
    "phx-viewport-bottom",
    "phx-auto-recover"
  ]

  @non_event_attrs [
    "phx-target",
    "phx-disable-with",
    "phx-update",
    "phx-debounce",
    "phx-throttle",
    "phx-hook",
    "phx-mounted",
    "phx-remove",
    "phx-connected",
    "phx-disconnected",
    "phx-trigger-action",
    "phx-no-unused-field",
    "phx-feedback-for",
    "phx-track-static",
    "phx-drop-target",
    "phx-no-format",
    "phx-no-curly-interpolation",
    "phx-page-loading",
    "phx-link",
    "phx-key"
  ]

  @dynamic_prefixes ["phx-value-"]

  @js_command_attrs @event_attrs ++
                      [
                        "phx-mounted",
                        "phx-remove",
                        "phx-connected",
                        "phx-disconnected"
                      ]

  @value_sets %{
    "phx-update" => ["replace", "stream", "ignore"]
  }

  @completion_attrs [
    {"phx-click", "LiveView click event", ~s[phx-click="${1:event}"]},
    {"phx-change", "LiveView form change event", ~s[phx-change="${1:event}"]},
    {"phx-submit", "LiveView form submit event", ~s[phx-submit="${1:event}"]},
    {"phx-focus", "LiveView focus event", ~s[phx-focus="${1:event}"]},
    {"phx-blur", "LiveView blur event", ~s[phx-blur="${1:event}"]},
    {"phx-keydown", "LiveView keydown event", ~s[phx-keydown="${1:event}"]},
    {"phx-keyup", "LiveView keyup event", ~s[phx-keyup="${1:event}"]},
    {"phx-window-focus", "LiveView window focus event", ~s[phx-window-focus="${1:event}"]},
    {"phx-window-blur", "LiveView window blur event", ~s[phx-window-blur="${1:event}"]},
    {"phx-window-keydown", "LiveView window keydown event", ~s[phx-window-keydown="${1:event}"]},
    {"phx-window-keyup", "LiveView window keyup event", ~s[phx-window-keyup="${1:event}"]},
    {"phx-click-away", "LiveView click-away event", ~s[phx-click-away="${1:event}"]},
    {"phx-viewport-top", "LiveView viewport top event", ~s[phx-viewport-top="${1:event}"]},
    {"phx-viewport-bottom", "LiveView viewport bottom event",
     ~s[phx-viewport-bottom="${1:event}"]},
    {"phx-target", "LiveView event target", "phx-target={${1:@myself}}"},
    {"phx-value-", "LiveView event payload value", ~s[phx-value-${1:name}="${2:value}"]},
    {"phx-debounce", "LiveView debounce interval", ~s[phx-debounce="${1:300}"]},
    {"phx-throttle", "LiveView throttle interval", ~s[phx-throttle="${1:1000}"]},
    {"phx-hook", "LiveView JavaScript hook", ~s[phx-hook="${1:HookName}"]},
    {"phx-update", "LiveView DOM patch mode", ~s[phx-update="${1|replace,stream,ignore|}"]},
    {"phx-mounted", "LiveView mounted JS command", "phx-mounted={${1:JS.show()}}"},
    {"phx-remove", "LiveView remove JS command", "phx-remove={${1:JS.hide()}}"},
    {"phx-connected", "LiveView connected JS command", "phx-connected={${1:JS.hide()}}"},
    {"phx-disconnected", "LiveView disconnected JS command", "phx-disconnected={${1:JS.show()}}"},
    {"phx-disable-with", "LiveView submit disable text", ~s[phx-disable-with="${1:Saving...}"]},
    {"phx-trigger-action", "LiveView trigger form action",
     "phx-trigger-action={${1:@trigger_action}}"},
    {"phx-no-unused-field", "Opt out of unused form field reporting", nil},
    {"phx-auto-recover", "LiveView form auto recover event", ~s[phx-auto-recover="${1:recover}"]},
    {"phx-feedback-for", "LiveView feedback field", ~s[phx-feedback-for="${1:field}"]},
    {"phx-track-static", "LiveView static asset tracking", nil},
    {"phx-drop-target", "LiveView upload drop target", ~s[phx-drop-target="${1:#upload}"]},
    {"phx-no-curly-interpolation", "Disable HEEx curly interpolation warnings", nil}
  ]

  @spec event_attrs() :: [String.t()]
  def event_attrs, do: @event_attrs

  @spec non_event_attrs() :: [String.t()]
  def non_event_attrs, do: @non_event_attrs

  @spec known_attrs() :: [String.t()]
  def known_attrs, do: @event_attrs ++ @non_event_attrs

  @spec dynamic_prefixes() :: [String.t()]
  def dynamic_prefixes, do: @dynamic_prefixes

  @spec completion_attrs() :: [{String.t(), String.t(), String.t() | nil}]
  def completion_attrs, do: @completion_attrs

  @spec completion_attrs_for(String.t() | nil, [String.t()]) :: [
          {String.t(), String.t(), String.t() | nil}
        ]
  def completion_attrs_for(tag, event_names \\ []) do
    @completion_attrs
    |> Enum.with_index()
    |> Enum.map(fn {attr, index} -> {event_detail(attr, event_names), index} end)
    |> Enum.sort_by(fn {{name, _detail, _insert_text}, index} ->
      {element_rank(tag, name), event_rank(name, event_names), index}
    end)
    |> Enum.map(fn {attr, _index} -> attr end)
  end

  @spec completion_attr(String.t()) :: {String.t(), String.t(), String.t() | nil} | nil
  def completion_attr(prefix) when is_binary(prefix) do
    Enum.find(@completion_attrs, fn {name, _detail, _insert_text} ->
      name == prefix or String.starts_with?(name, prefix)
    end)
  end

  @spec event_attr?(String.t()) :: boolean()
  def event_attr?(name) when is_binary(name), do: name in @event_attrs
  def event_attr?(_name), do: false

  @spec js_command_attr?(String.t()) :: boolean()
  def js_command_attr?(name) when is_binary(name), do: name in @js_command_attrs
  def js_command_attr?(_name), do: false

  @spec known_attr?(String.t()) :: boolean()
  def known_attr?(name) when is_binary(name) do
    name in known_attrs() or Enum.any?(@dynamic_prefixes, &String.starts_with?(name, &1))
  end

  def known_attr?(_name), do: false

  @spec value_set(String.t()) :: {:ok, [String.t()]} | :error
  def value_set(name) when is_binary(name), do: Map.fetch(@value_sets, name)
  def value_set(_name), do: :error

  defp event_detail({name, _detail, insert_text}, [event_name | _rest])
       when name in @event_attrs do
    {name, "LiveView event: #{event_name}", insert_text}
  end

  defp event_detail(attr, _event_names), do: attr

  defp element_rank("form", "phx-submit"), do: 0
  defp element_rank("form", "phx-change"), do: 1
  defp element_rank("form", "phx-auto-recover"), do: 2

  defp element_rank(tag, "phx-focus") when tag in ["input", "button"], do: 0
  defp element_rank(tag, "phx-blur") when tag in ["input", "button"], do: 1
  defp element_rank(tag, "phx-keydown") when tag in ["input", "button"], do: 2
  defp element_rank(tag, "phx-keyup") when tag in ["input", "button"], do: 3

  defp element_rank(_tag, _name), do: 10

  defp event_rank(name, [_event_name | _rest]) do
    if name in @event_attrs, do: 0, else: 1
  end

  defp event_rank(_name, _event_names), do: 0
end
