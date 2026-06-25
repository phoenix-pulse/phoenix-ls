defmodule PhoenixLS.Features.Completion.Snippets do
  @moduledoc """
  Small static Phoenix and HTML completion set.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @html_tags ["div", "span", "button", "form", "section", "article"]
  @heex_attrs [
    {":for", "HEEx comprehension", ":for={${1:item} <- ${2:@items}}"},
    {":if", "HEEx conditional render", ":if={${1:@condition}}"},
    {":let", "HEEx yielded value binding", ":let={${1:var}}"},
    {":key", "HEEx keyed comprehension item", ":key={${1:item.id}}"}
  ]

  @phoenix_attrs [
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
    {"phx-auto-recover", "LiveView form auto recover event", ~s[phx-auto-recover="${1:recover}"]},
    {"phx-feedback-for", "LiveView feedback field", ~s[phx-feedback-for="${1:field}"]},
    {"phx-track-static", "LiveView static asset tracking", nil},
    {"phx-drop-target", "LiveView upload drop target", ~s[phx-drop-target="${1:#upload}"]},
    {"phx-no-curly-interpolation", "Disable HEEx curly interpolation warnings", nil}
  ]

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :tag_name, prefix: prefix, closing?: false}, _facts) do
    prefix = prefix || ""

    if snippet_tag_prefix?(prefix) do
      @html_tags
      |> Enum.map(&tag_item/1)
      |> prefixed_items(prefix)
    else
      []
    end
  end

  def complete(%CursorContext{kind: :attribute_name, prefix: prefix}, _facts) do
    @heex_attrs
    |> Enum.map(&special_attribute_item/1)
    |> Kernel.++(Enum.map(@phoenix_attrs, &phoenix_attribute_item/1))
    |> prefixed_items(prefix || "")
  end

  def complete(_context, _facts), do: []

  defp snippet_tag_prefix?("." <> _prefix), do: false
  defp snippet_tag_prefix?(":" <> _prefix), do: false
  defp snippet_tag_prefix?(""), do: true

  defp snippet_tag_prefix?(<<first::utf8, _rest::binary>>) do
    first not in ?A..?Z
  end

  defp tag_item(tag) do
    {tag,
     %CompletionItem{
       label: tag,
       kind: CompletionItemKind.snippet(),
       detail: "HTML <#{tag}>",
       insert_text: tag,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "html_tag", "id" => tag}
     }}
  end

  defp special_attribute_item({attribute, detail, insert_text}) do
    {attribute,
     %CompletionItem{
       label: attribute,
       kind: CompletionItemKind.property(),
       detail: detail,
       insert_text: insert_text,
       insert_text_format: InsertTextFormat.snippet(),
       data: %{"kind" => "heex_special_attr", "id" => attribute}
     }}
  end

  defp phoenix_attribute_item({attribute, detail, nil}) do
    {attribute,
     %CompletionItem{
       label: attribute,
       kind: CompletionItemKind.property(),
       detail: detail,
       insert_text: attribute,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "phoenix_attr", "id" => attribute}
     }}
  end

  defp phoenix_attribute_item({attribute, detail, insert_text}) do
    {attribute,
     %CompletionItem{
       label: attribute,
       kind: CompletionItemKind.property(),
       detail: detail,
       insert_text: insert_text,
       insert_text_format: InsertTextFormat.snippet(),
       data: %{"kind" => "phoenix_attr", "id" => attribute}
     }}
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
