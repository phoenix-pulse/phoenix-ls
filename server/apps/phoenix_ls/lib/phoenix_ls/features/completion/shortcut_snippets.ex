defmodule PhoenixLS.Features.Completion.ShortcutSnippets do
  @moduledoc """
  Source-aware Phoenix and LiveView shortcut snippets.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.{CompletionItem, Position, Range, TextEdit}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @component_kind CompletionItemKind.snippet()
  @event_kind CompletionItemKind.event()

  @shortcuts [
    {".live", "Phoenix component shortcut",
     ~S(<.live_component module={${1:Module}} id="${2:id}" />), @component_kind},
    {".modal", "Phoenix component shortcut", ~S(<.modal id="${1:modal-id}">
  <:title>${2:Modal Title}</:title>
  ${3:Modal content}
</.modal>), @component_kind},
    {".form", "Phoenix component shortcut", ~S(<.simple_form for={@form} phx-submit="${1:save}">
  <.input field={@form[:${2:field}]} label="${3:Label}" />
  <:actions>
    <.button>Save</.button>
  </:actions>
</.simple_form>), @component_kind},
    {".table", "Phoenix component shortcut", ~S(<.table rows={@${1:items}}>
  <:col :let={item} label="${2:Label}">{item.${3:field}}</:col>
</.table>), @component_kind},
    {".link", "Phoenix component shortcut",
     ~S(<.link navigate={~p"/${1:path}"}>${2:Link text}</.link>), @component_kind},
    {".button", "Phoenix component shortcut",
     ~S(<.button phx-click="${1:action}">${2:Button text}</.button>), @component_kind},
    {".input", "Phoenix component shortcut",
     ~S(<.input field={@form[:${1:field}]} label="${2:Label}" />), @component_kind},
    {"stream", "Phoenix stream shortcut",
     ~S(<div id="${1:stream_name}-stream" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.${1:stream_name}} id={dom_id}>
    {item.${2:field}}
  </div>
</div>), @component_kind},
    {"form.phx", "Phoenix pattern shortcut", ~S(<form phx-submit="${1:save}">
  <input type="text" name="${2:field}" value={@${2:field}} />
  <button type="submit">Submit</button>
</form>), @component_kind},
    {"link.phx", "Phoenix pattern shortcut",
     ~S(<a href="#" phx-click="${1:action}">${2:Link text}</a>), @component_kind},
    {"btn.phx", "Phoenix pattern shortcut",
     ~S(<button type="button" phx-click="${1:action}">${2:Button text}</button>),
     @component_kind},
    {"button.phx", "Phoenix pattern shortcut",
     ~S(<button type="button" phx-click="${1:action}">${2:Button text}</button>),
     @component_kind},
    {"input.phx", "Phoenix pattern shortcut",
     ~S(<input type="text" name="${1:field}" value={@${1:field}} phx-blur="validate" />),
     @component_kind},
    {"div.loading", "Phoenix pattern shortcut",
     ~S(<div :if={@loading} class="spinner">Loading...</div>), @component_kind},
    {"div.error", "Phoenix pattern shortcut",
     ~S(<div :if={@error} class="alert alert-danger">{@error}</div>), @component_kind},
    {"@click", "Phoenix event shortcut", ~S(phx-click="${1:action}"), @event_kind},
    {"@submit", "Phoenix event shortcut", ~S(phx-submit="${1:action}"), @event_kind},
    {"@change", "Phoenix event shortcut", ~S(phx-change="${1:action}"), @event_kind},
    {"@blur", "Phoenix event shortcut", ~S(phx-blur="${1:action}"), @event_kind},
    {"@focus", "Phoenix event shortcut", ~S(phx-focus="${1:action}"), @event_kind},
    {"@keydown", "Phoenix event shortcut", ~S(phx-keydown="${1:action}"), @event_kind},
    {"@keyup", "Phoenix event shortcut", ~S(phx-keyup="${1:action}"), @event_kind},
    {"@input", "Phoenix event shortcut", ~S(phx-input="${1:action}"), @event_kind},
    {"@click.target", "Phoenix event shortcut", ~S(phx-click="${1:action}" phx-target={@myself}),
     @event_kind},
    {"@click.debounce", "Phoenix event shortcut",
     ~S(phx-click="${1:action}" phx-debounce="${2:300}"), @event_kind},
    {"@click.throttle", "Phoenix event shortcut",
     ~S(phx-click="${1:action}" phx-throttle="${2:1000}"), @event_kind},
    {"@submit.target", "Phoenix event shortcut",
     ~S(phx-submit="${1:action}" phx-target={@myself}), @event_kind},
    {"@change.debounce", "Phoenix event shortcut",
     ~S(phx-change="${1:action}" phx-debounce="${2:300}"), @event_kind},
    {"@blur.debounce", "Phoenix event shortcut",
     ~S(phx-blur="${1:action}" phx-debounce="${2:300}"), @event_kind},
    {"input.text", "Phoenix form shortcut",
     ~S(<input type="text" name="${1:field}" value={@${1:field}} phx-blur="validate" />),
     @component_kind},
    {"input.email", "Phoenix form shortcut",
     ~S(<input type="email" name="email" value={@email} required phx-blur="validate" />),
     @component_kind},
    {"input.password", "Phoenix form shortcut",
     ~S(<input type="password" name="password" required phx-blur="validate" />), @component_kind},
    {"input.number", "Phoenix form shortcut",
     ~S(<input type="number" name="${1:field}" value={@${1:field}} phx-blur="validate" />),
     @component_kind},
    {"select.phx", "Phoenix form shortcut", ~S(<select name="${1:field}" phx-change="${2:update}">
  <option :for={opt <- @${3:options}} value={opt.value}>{opt.label}</option>
</select>), @component_kind},
    {"checkbox.phx", "Phoenix form shortcut",
     ~S(<input type="checkbox" name="${1:field}" checked={@${1:field}} phx-click="${2:toggle}" />),
     @component_kind},
    {"textarea.phx", "Phoenix form shortcut",
     ~S(<textarea name="${1:field}" phx-blur="validate">{@${1:field}}</textarea>),
     @component_kind},
    {"link.nav", "Phoenix route shortcut",
     ~S(<.link navigate={~p"/${1:path}"}>${2:Link text}</.link>), @component_kind},
    {"link.patch", "Phoenix route shortcut",
     ~S(<.link patch={~p"/${1:path}"}>${2:Link text}</.link>), @component_kind},
    {"link.href", "Phoenix route shortcut",
     ~S(<.link href={~p"/${1:path}"}>${2:Link text}</.link>), @component_kind},
    {"a.nav", "Phoenix route shortcut", ~S(<a href={~p"/${1:path}"}>${2:Link text}</a>),
     @component_kind},
    {"a.patch", "Phoenix route shortcut",
     ~S(<a href={~p"/${1:path}"} data-phx-link="patch" data-phx-link-state="push">${2:Link text}</a>),
     @component_kind},
    {"a.href", "Phoenix route shortcut", ~S(<a href={~p"/${1:path}"}>${2:Link text}</a>),
     @component_kind},
    {"img.static", "Phoenix asset shortcut",
     ~S(<img src={~p"/images/${1:filename}"} alt="${2:Alt text}" />), @component_kind},
    {"link.css", "Phoenix asset shortcut",
     ~S(<link rel="stylesheet" href={~p"/assets/${1:filename}.css"} />), @component_kind},
    {"script.js", "Phoenix asset shortcut",
     ~S(<script src={~p"/assets/${1:filename}.js"}></script>), @component_kind},
    {".hero", "Phoenix layout shortcut", ~S(<div class="hero">
  <h1>${1:Hero Title}</h1>
  <p>${2:Hero description}</p>
</div>), @component_kind},
    {".card", "Phoenix layout shortcut", ~S(<div class="card">
  <div class="card-header">${1:Header}</div>
  <div class="card-body">${2:Content}</div>
</div>), @component_kind},
    {".grid", "Phoenix layout shortcut", ~S(<div class="grid grid-cols-${1:3} gap-4">
  ${2:Grid items}
</div>), @component_kind},
    {".container", "Phoenix layout shortcut", ~S(<div class="container mx-auto px-4">
  ${1:Content}
</div>), @component_kind},
    {".section", "Phoenix layout shortcut", ~S(<section class="${1:section-class}">
  <h2>${2:Section Title}</h2>
  ${3:Section content}
</section>), @component_kind}
  ]

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, _facts) when is_binary(source) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, trigger, detail, snippet, kind} <- matching_shortcut(source, offset),
         {:ok, range} <- replacement_range(source, offset, trigger) do
      [
        %CompletionItem{
          label: trigger,
          kind: kind,
          detail: detail,
          insert_text_format: InsertTextFormat.snippet(),
          text_edit: %TextEdit{range: range, new_text: snippet},
          data: %{"kind" => "shortcut_snippet", "id" => trigger}
        }
      ]
    else
      _no_shortcut -> []
    end
  end

  defp matching_shortcut(source, offset) do
    source_before_cursor = binary_part(source, 0, offset)

    Enum.find_value(@shortcuts, :error, fn {trigger, detail, snippet, kind} ->
      if String.ends_with?(source_before_cursor, trigger) and
           trigger_boundary?(source, offset, trigger) do
        {:ok, trigger, detail, snippet, kind}
      else
        false
      end
    end)
  end

  defp trigger_boundary?(source, offset, trigger) do
    start_offset = offset - byte_size(trigger)

    cond do
      start_offset < 0 -> false
      start_offset == 0 -> true
      true -> source |> binary_part(start_offset - 1, 1) |> whitespace?()
    end
  end

  defp replacement_range(source, offset, trigger) do
    start_offset = offset - byte_size(trigger)

    with {:ok, start_position} <- Positions.offset_to_lsp_position(source, start_offset),
         {:ok, end_position} <- Positions.offset_to_lsp_position(source, offset) do
      {:ok, %Range{start: position(start_position), end: position(end_position)}}
    end
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end

  defp whitespace?(char), do: char in [" ", "\t", "\n", "\r"]
end
