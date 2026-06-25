defmodule PhoenixLS.Features.Completion.HTMLAttributes do
  @moduledoc """
  Completion items for HTML attributes and predefined attribute values.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @global_attrs [
    {"id", "Unique element identifier", []},
    {"class", "CSS classes", []},
    {"style", "Inline CSS styles", []},
    {"title", "Advisory information", []},
    {"lang", "Language code", ["en", "es", "fr", "de", "ja", "zh", "pt"]},
    {"dir", "Text direction", ["ltr", "rtl", "auto"]},
    {"translate", "Translation hint", ["yes", "no"]},
    {"tabindex", "Tab order", []},
    {"accesskey", "Keyboard shortcut", []},
    {"hidden", "Hidden element", [], :boolean},
    {"contenteditable", "Editable content", ["true", "false"]},
    {"draggable", "Draggable element", ["true", "false"]},
    {"spellcheck", "Spell checking", ["true", "false"]},
    {"autocapitalize", "Auto-capitalization behavior",
     ["off", "none", "on", "sentences", "words", "characters"]},
    {"data-", "Custom data attribute", [], {:snippet, ~s[data-${1:name}="${2:value}"]}}
  ]

  @aria_attrs [
    {"role", "ARIA role",
     [
       "button",
       "link",
       "navigation",
       "main",
       "banner",
       "contentinfo",
       "search",
       "form",
       "region",
       "article",
       "dialog",
       "alert",
       "status"
     ]},
    {"aria-label", "Accessible label", []},
    {"aria-labelledby", "ID reference to labeling elements", []},
    {"aria-describedby", "ID reference to describing elements", []},
    {"aria-hidden", "Hidden from assistive technologies", ["true", "false"]},
    {"aria-expanded", "Expanded state", ["true", "false"]},
    {"aria-disabled", "Disabled state", ["true", "false"]},
    {"aria-checked", "Checked state", ["true", "false", "mixed"]},
    {"aria-selected", "Selected state", ["true", "false"]},
    {"aria-pressed", "Pressed state", ["true", "false", "mixed"]},
    {"aria-current", "Current item indicator", ["page", "step", "location", "date", "time"]},
    {"aria-invalid", "Validation state", ["true", "false", "grammar", "spelling"]},
    {"aria-required", "Required field", ["true", "false"]},
    {"aria-readonly", "Read-only field", ["true", "false"]},
    {"aria-live", "Live region politeness", ["off", "polite", "assertive"]},
    {"aria-atomic", "Announce entire region on change", ["true", "false"]},
    {"aria-relevant", "What changes to announce", ["additions", "removals", "text", "all"]},
    {"aria-controls", "IDs of controlled elements", []},
    {"aria-owns", "IDs of owned elements", []},
    {"aria-flowto", "ID of next element in reading order", []},
    {"aria-valuemin", "Minimum value", []},
    {"aria-valuemax", "Maximum value", []},
    {"aria-valuenow", "Current value", []},
    {"aria-valuetext", "Human-readable value", []}
  ]

  @audio_attrs [
    {"src", "Audio source URL", []},
    {"controls", "Show playback controls", [], :boolean},
    {"autoplay", "Auto-play on load", [], :boolean},
    {"loop", "Loop playback", [], :boolean},
    {"muted", "Muted by default", [], :boolean},
    {"preload", "Preload strategy", ["none", "metadata", "auto"]},
    {"crossorigin", "CORS mode", ["anonymous", "use-credentials"]},
    {"width", "Audio width", []},
    {"height", "Audio height", []}
  ]

  @video_attrs [
    {"src", "Video source URL", []},
    {"controls", "Show playback controls", [], :boolean},
    {"autoplay", "Auto-play on load", [], :boolean},
    {"loop", "Loop playback", [], :boolean},
    {"muted", "Muted by default", [], :boolean},
    {"preload", "Preload strategy", ["none", "metadata", "auto"]},
    {"crossorigin", "CORS mode", ["anonymous", "use-credentials"]},
    {"width", "Video width", []},
    {"height", "Video height", []},
    {"poster", "Poster image URL", []},
    {"playsinline", "Play inline on mobile", [], :boolean}
  ]

  @range_attrs [
    {"value", "Meter value", []},
    {"min", "Minimum value", []},
    {"max", "Maximum value", []},
    {"low", "Low threshold", []},
    {"high", "High threshold", []},
    {"optimum", "Optimal value", []}
  ]

  @table_cell_attrs [
    {"colspan", "Number of columns to span", []},
    {"rowspan", "Number of rows to span", []},
    {"headers", "Header cell IDs", []}
  ]

  @element_attrs %{
    "a" => [
      {"href", "Link destination URL", []},
      {"target", "Where to open the link", ["_blank", "_self", "_parent", "_top"]},
      {"rel", "Link relationship",
       ["noopener", "noreferrer", "nofollow", "external", "alternate", "author", "next", "prev"]},
      {"download", "Download filename", []},
      {"hreflang", "Language of linked resource", []},
      {"type", "MIME type of linked resource", []},
      {"ping", "URLs to ping when link is clicked", []},
      {"referrerpolicy", "Referrer policy",
       [
         "no-referrer",
         "origin",
         "same-origin",
         "strict-origin",
         "strict-origin-when-cross-origin"
       ]}
    ],
    "area" => [
      {"alt", "Alternative text", []},
      {"coords", "Coordinates for clickable area", []},
      {"shape", "Shape of clickable area", ["rect", "circle", "poly", "default"]},
      {"href", "Link destination URL", []},
      {"target", "Where to open the link", ["_blank", "_self", "_parent", "_top"]},
      {"download", "Download filename", []},
      {"rel", "Link relationship", ["noopener", "noreferrer", "nofollow"]}
    ],
    "audio" => @audio_attrs,
    "base" => [
      {"href", "Base URL for relative URLs", []},
      {"target", "Default target for links", ["_blank", "_self", "_parent", "_top"]}
    ],
    "button" => [
      {"type", "Button type", ["submit", "reset", "button"]},
      {"name", "Button name", []},
      {"value", "Button value", []},
      {"disabled", "Disabled button", [], :boolean},
      {"autofocus", "Auto-focus on page load", [], :boolean},
      {"form", "Associated form ID", []},
      {"formaction", "Override form action URL", []},
      {"formmethod", "Override form method", ["get", "post"]},
      {"formnovalidate", "Skip form validation", [], :boolean}
    ],
    "canvas" => [
      {"width", "Canvas width", []},
      {"height", "Canvas height", []}
    ],
    "details" => [{"open", "Expanded state", [], :boolean}],
    "dialog" => [{"open", "Open dialog", [], :boolean}],
    "form" => [
      {"action", "URL to submit form data", []},
      {"method", "HTTP method for form submission", ["get", "post"]},
      {"enctype", "Form data encoding type",
       ["application/x-www-form-urlencoded", "multipart/form-data", "text/plain"]},
      {"target", "Where to display form response", ["_blank", "_self", "_parent", "_top"]},
      {"novalidate", "Skip HTML5 validation", [], :boolean},
      {"autocomplete", "Form autocomplete behavior", ["on", "off"]},
      {"name", "Form name", []},
      {"accept-charset", "Character encodings for submission", ["UTF-8", "ISO-8859-1"]}
    ],
    "iframe" => [
      {"src", "Frame source URL", []},
      {"srcdoc", "Inline HTML document content", []},
      {"name", "Frame name", []},
      {"width", "Frame width", []},
      {"height", "Frame height", []},
      {"sandbox", "Security restrictions",
       ["allow-forms", "allow-scripts", "allow-same-origin", "allow-popups", "allow-modals"]},
      {"allow", "Feature policy", ["camera", "microphone", "geolocation", "fullscreen"]},
      {"loading", "Loading strategy", ["lazy", "eager"]},
      {"referrerpolicy", "Referrer policy", ["no-referrer", "origin", "same-origin"]}
    ],
    "img" => [
      {"src", "Image URL", []},
      {"alt", "Alternative text", []},
      {"width", "Image width", []},
      {"height", "Image height", []},
      {"loading", "Loading strategy", ["lazy", "eager"]},
      {"decoding", "Image decode strategy", ["async", "sync", "auto"]},
      {"srcset", "Responsive image sources", []},
      {"sizes", "Responsive image sizes", []},
      {"crossorigin", "CORS mode", ["anonymous", "use-credentials"]},
      {"fetchpriority", "Fetch priority hint", ["high", "low", "auto"]},
      {"ismap", "Server-side image map", [], :boolean},
      {"usemap", "Client-side image map reference", []}
    ],
    "input" => [
      {"type", "Input control type",
       [
         "text",
         "email",
         "password",
         "number",
         "tel",
         "url",
         "search",
         "date",
         "datetime-local",
         "time",
         "month",
         "week",
         "checkbox",
         "radio",
         "file",
         "submit",
         "button",
         "reset",
         "hidden",
         "range",
         "color"
       ]},
      {"name", "Form control name", []},
      {"value", "Current value", []},
      {"placeholder", "Placeholder text", []},
      {"required", "Required field", [], :boolean},
      {"disabled", "Disabled field", [], :boolean},
      {"readonly", "Read-only field", [], :boolean},
      {"checked", "Checked state", [], :boolean},
      {"autofocus", "Auto-focus on page load", [], :boolean},
      {"autocomplete", "Autocomplete hint",
       ["on", "off", "name", "email", "username", "new-password", "current-password", "tel"]},
      {"pattern", "Validation pattern", []},
      {"min", "Minimum value", []},
      {"max", "Maximum value", []},
      {"step", "Value increment step", []},
      {"maxlength", "Maximum character length", []},
      {"minlength", "Minimum character length", []},
      {"size", "Visible width in characters", []},
      {"multiple", "Allow multiple values", [], :boolean},
      {"accept", "Accepted file types",
       ["image/*", "video/*", "audio/*", ".jpg,.png,.gif", ".pdf"]},
      {"capture", "Camera capture mode", ["user", "environment"]},
      {"list", "Datalist ID reference", []},
      {"form", "Associated form ID", []},
      {"formaction", "Override form action URL", []},
      {"formmethod", "Override form method", ["get", "post"]},
      {"formnovalidate", "Skip form validation", [], :boolean}
    ],
    "label" => [{"for", "Associated form control ID", []}],
    "link" => [
      {"href", "Resource URL", []},
      {"rel", "Link relationship",
       ["stylesheet", "icon", "preload", "prefetch", "dns-prefetch", "preconnect", "alternate"]},
      {"type", "MIME type of linked resource", ["text/css", "image/x-icon", "image/png"]},
      {"media", "Media query", ["screen", "print", "(max-width: 600px)"]},
      {"sizes", "Icon sizes", ["16x16", "32x32", "192x192", "any"]},
      {"crossorigin", "CORS mode", ["anonymous", "use-credentials"]},
      {"integrity", "Subresource integrity hash", []},
      {"referrerpolicy", "Referrer policy", ["no-referrer", "origin", "same-origin"]},
      {"as", "Preload resource type",
       ["audio", "document", "embed", "fetch", "font", "image", "script", "style", "worker"]},
      {"fetchpriority", "Fetch priority hint", ["high", "low", "auto"]}
    ],
    "meta" => [
      {"charset", "Character encoding", ["UTF-8"]},
      {"name", "Metadata name", ["viewport", "description", "keywords", "author", "theme-color"]},
      {"content", "Metadata value", []},
      {"http-equiv", "HTTP header directive",
       ["content-type", "refresh", "X-UA-Compatible", "content-security-policy"]}
    ],
    "meter" => @range_attrs,
    "ol" => [
      {"reversed", "Reverse numbering order", [], :boolean},
      {"start", "Starting number", []},
      {"type", "Numbering type", ["1", "a", "A", "i", "I"]}
    ],
    "option" => [
      {"value", "Option value", []},
      {"selected", "Selected by default", [], :boolean},
      {"disabled", "Disabled option", [], :boolean},
      {"label", "Option label", []}
    ],
    "output" => [
      {"for", "Contributing form control IDs", []},
      {"form", "Associated form ID", []},
      {"name", "Output name", []}
    ],
    "progress" => [
      {"value", "Current progress value", []},
      {"max", "Maximum value", []}
    ],
    "script" => [
      {"src", "Script file URL", []},
      {"type", "Script MIME type", ["module", "text/javascript", "application/javascript"]},
      {"async", "Async execution", [], :boolean},
      {"defer", "Deferred execution", [], :boolean},
      {"crossorigin", "CORS mode", ["anonymous", "use-credentials"]},
      {"integrity", "Subresource integrity hash", []},
      {"nomodule", "Skip in module-aware browsers", [], :boolean},
      {"referrerpolicy", "Referrer policy", ["no-referrer", "origin", "same-origin"]}
    ],
    "select" => [
      {"name", "Control name", []},
      {"multiple", "Allow multiple selection", [], :boolean},
      {"size", "Number of visible options", []},
      {"required", "Required field", [], :boolean},
      {"disabled", "Disabled field", [], :boolean},
      {"autofocus", "Auto-focus on page load", [], :boolean},
      {"autocomplete", "Autocomplete behavior", ["on", "off"]}
    ],
    "source" => [
      {"src", "Media source URL", []},
      {"type", "MIME type of media source",
       ["video/mp4", "video/webm", "video/ogg", "audio/mpeg", "audio/ogg", "audio/wav"]},
      {"media", "Media query for source selection", []},
      {"sizes", "Image sizes", []},
      {"srcset", "Image source set", []}
    ],
    "style" => [
      {"media", "Media query", ["screen", "print", "(max-width: 600px)"]},
      {"type", "MIME type", ["text/css"]}
    ],
    "td" => @table_cell_attrs,
    "textarea" => [
      {"name", "Control name", []},
      {"rows", "Visible rows", []},
      {"cols", "Visible columns", []},
      {"placeholder", "Placeholder text", []},
      {"required", "Required field", [], :boolean},
      {"disabled", "Disabled field", [], :boolean},
      {"readonly", "Read-only field", [], :boolean},
      {"maxlength", "Maximum character length", []},
      {"minlength", "Minimum character length", []},
      {"autocomplete", "Autocomplete behavior", ["on", "off"]},
      {"autofocus", "Auto-focus on page load", [], :boolean},
      {"wrap", "Text wrapping mode", ["soft", "hard"]}
    ],
    "th" =>
      @table_cell_attrs ++
        [{"scope", "Scope of header cell", ["row", "col", "rowgroup", "colgroup"]}],
    "time" => [{"datetime", "Machine-readable datetime", []}],
    "track" => [
      {"src", "Track file URL", []},
      {"kind", "Track type", ["subtitles", "captions", "descriptions", "chapters", "metadata"]},
      {"srclang", "Track language code", ["en", "es", "fr", "de", "ja", "zh"]},
      {"label", "Track label", []},
      {"default", "Default track", [], :boolean}
    ],
    "video" => @video_attrs
  }

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :attribute_name, tag: tag, prefix: prefix}, _facts) do
    with {:ok, html_tag} <- html_tag(tag) do
      html_tag
      |> attributes_for()
      |> Enum.map(&attribute_item(&1, html_tag))
      |> prefixed_items(prefix || "")
    else
      :error -> []
    end
  end

  def complete(
        %CursorContext{kind: :attribute_value, tag: tag, attribute: attribute, prefix: prefix},
        _facts
      ) do
    with {:ok, html_tag} <- html_tag(tag),
         {:ok, values} <- values_for(html_tag, attribute) do
      values
      |> Enum.map(&value_item(&1, html_tag, attribute))
      |> prefixed_items(prefix || "")
    else
      :error -> []
    end
  end

  def complete(_context, _facts), do: []

  defp html_tag(nil), do: :error
  defp html_tag("." <> _component), do: :error
  defp html_tag(":" <> _slot), do: :error

  defp html_tag(tag) when is_binary(tag) do
    cond do
      String.contains?(tag, ".") -> :error
      tag != String.downcase(tag) -> :error
      true -> {:ok, tag}
    end
  end

  defp attributes_for(tag) do
    Map.get(@element_attrs, tag, []) ++ @global_attrs ++ @aria_attrs
  end

  defp values_for(tag, attribute) do
    tag
    |> attributes_for()
    |> Enum.find(&match_name?(&1, attribute))
    |> case do
      nil -> :error
      {_name, _detail, []} -> :error
      {_name, _detail, [], _kind} -> :error
      {_name, _detail, values} -> {:ok, values}
      {_name, _detail, values, _kind} -> {:ok, values}
    end
  end

  defp match_name?({name, _detail, _values}, attribute), do: name == attribute
  defp match_name?({name, _detail, _values, _kind}, attribute), do: name == attribute

  defp attribute_item(attribute, tag) do
    name = attr_name(attribute)

    {name,
     %CompletionItem{
       label: name,
       kind: CompletionItemKind.property(),
       detail: attr_detail(attribute),
       insert_text: attr_insert_text(attribute),
       insert_text_format: attr_insert_text_format(attribute),
       data: %{"kind" => "html_attr", "tag" => tag, "name" => name}
     }}
  end

  defp value_item(value, tag, attribute) do
    {value,
     %CompletionItem{
       label: value,
       kind: CompletionItemKind.value(),
       detail: "#{attribute} value for <#{tag}>",
       insert_text: value,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{
         "kind" => "html_attr_value",
         "tag" => tag,
         "attribute" => attribute,
         "value" => value
       }
     }}
  end

  defp attr_name({name, _detail, _values}), do: name
  defp attr_name({name, _detail, _values, _kind}), do: name

  defp attr_detail({_name, detail, _values}), do: detail
  defp attr_detail({_name, detail, _values, _kind}), do: detail

  defp attr_insert_text({name, _detail, []}), do: ~s[#{name}="${1:value}"]
  defp attr_insert_text({name, _detail, values}), do: choice_snippet(name, values)
  defp attr_insert_text({name, _detail, _values, :boolean}), do: name
  defp attr_insert_text({_name, _detail, _values, {:snippet, snippet}}), do: snippet

  defp attr_insert_text_format({_name, _detail, _values, :boolean}),
    do: InsertTextFormat.plain_text()

  defp attr_insert_text_format(_attribute), do: InsertTextFormat.snippet()

  defp choice_snippet(name, values) do
    ~s[#{name}="${1|#{Enum.join(values, ",")}|}"]
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
