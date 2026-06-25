defmodule PhoenixLS.Features.Completion.Resolve do
  @moduledoc """
  Resolves additional completion item metadata carried in item data.
  """

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.URI, as: SupportURI

  @kind_descriptions %{
    "route" => "A verified Phoenix route indexed from router routes.",
    "asset" => "A static asset available through verified route paths.",
    "template" => "A Phoenix controller render template candidate.",
    "component" => "A Phoenix function component indexed from source.",
    "component_attr" => "A Phoenix component attribute declared with attr/3.",
    "component_slot" => "A Phoenix component slot declared with slot/3.",
    "component_slot_attr" => "A Phoenix component slot attribute declared inside a slot.",
    "schema_field" => "An Ecto schema field indexed from source.",
    "schema_association" => "An Ecto schema association indexed from source.",
    "assign" => "A LiveView assign discovered from source.",
    "live_event" => "A LiveView event handler discovered from handle_event/3.",
    "live_view_js_command" => "A Phoenix.LiveView.JS command for client-side interactions.",
    "html_attr" => "An HTML attribute valid for this tag.",
    "html_attr_value" => "An HTML attribute value valid for this attribute.",
    "heex_special_attr" => "A HEEx special attribute.",
    "phoenix_attr" => "A Phoenix attribute for HEEx templates.",
    "html_tag" => "An HTML tag snippet.",
    "shortcut_snippet" => "A Phoenix shortcut snippet.",
    "phx_value_field" => "A `phx-value-*` field derived from the surrounding schema-backed loop.",
    "elixir_fallback" => "An Elixir fallback completion for generic expression contexts."
  }

  @spec resolve(CompletionItem.t()) :: CompletionItem.t()
  def resolve(%CompletionItem{} = item) do
    resolve(item, [])
  end

  @spec resolve(CompletionItem.t(), [Fact.t()]) :: CompletionItem.t()
  def resolve(%CompletionItem{} = item, facts) when is_list(facts) do
    case documentation(item, facts) do
      nil -> item
      documentation -> %{item | documentation: documentation}
    end
  end

  defp documentation(%CompletionItem{} = item, facts) do
    lines =
      [
        documentation(item),
        source_context(item, facts)
      ]
      |> Enum.reject(&blank?/1)

    case lines do
      [] -> nil
      lines -> Enum.join(lines, "\n\n")
    end
  end

  defp documentation(%CompletionItem{data: %{"documentation" => documentation}})
       when is_binary(documentation) do
    documentation
  end

  defp documentation(%CompletionItem{
         detail: detail,
         data: %{"kind" => "route_helper", "helper" => helper}
       })
       when is_binary(helper) do
    route_helper_documentation(detail || "Routes.#{helper}")
  end

  defp documentation(%CompletionItem{data: %{"kind" => kind}} = item) when is_binary(kind) do
    case Map.fetch(@kind_descriptions, kind) do
      {:ok, description} -> completion_documentation(item, description)
      :error -> nil
    end
  end

  defp documentation(_item), do: nil

  defp source_context(%CompletionItem{data: %{"id" => id}}, facts) when is_binary(id) do
    facts
    |> Enum.find(&(&1.id == id))
    |> source_context_for_fact()
  end

  defp source_context(_item, _facts), do: nil

  defp source_context_for_fact(nil), do: nil

  defp source_context_for_fact(%Fact{} = fact) do
    [
      source_location_line(fact),
      source_module_line(fact)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  defp source_location_line(%Fact{} = fact) do
    "Source: #{source_path(fact.uri)}:#{fact.range.start.line + 1}:#{fact.range.start.character + 1}"
  end

  defp source_module_line(%Fact{data: %{module: module}}) when is_binary(module),
    do: "Module: #{module}"

  defp source_module_line(_fact), do: nil

  defp source_path(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, _reason} -> uri
    end
  end

  defp route_helper_documentation(helper) do
    """
    #{helper}

    Phoenix route helper generated from indexed router routes. Prefer verified `~p` paths for new code when possible.
    """
    |> String.trim()
  end

  defp completion_documentation(%CompletionItem{} = item, description) do
    item
    |> documentation_lines(description)
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp documentation_lines(%CompletionItem{} = item, description) do
    [
      completion_title(item),
      description
    ]
  end

  defp completion_title(%CompletionItem{detail: detail}) when is_binary(detail), do: detail
  defp completion_title(%CompletionItem{label: label}) when is_binary(label), do: label
  defp completion_title(_item), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
