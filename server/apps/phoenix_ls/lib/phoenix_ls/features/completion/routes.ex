defmodule PhoenixLS.Features.Completion.Routes do
  @moduledoc """
  Completion items for verified `~p` route paths.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.{Facts, RouteHelpers}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    case route_helper_prefix(prefix) do
      {:ok, helper_prefix} ->
        route_helper_items(facts, helper_prefix)

      :error ->
        complete_route_paths(prefix, facts)
    end
  end

  def complete(_context, _facts), do: []

  defp complete_route_paths(prefix, facts) do
    case route_prefix(prefix) do
      {:ok, typed_path} ->
        facts
        |> Facts.by_kind(:route)
        |> Enum.map(&route_item/1)
        |> prefixed_items(typed_path)

      :error ->
        []
    end
  end

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    complete(source, nil, position, facts)
  end

  @spec complete(String.t(), String.t() | nil, Positions.lsp_position(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(source, uri, position, facts)
      when is_binary(source) and (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    case RouteHelpers.prefix(source, position) do
      {:ok, helper_prefix} ->
        route_helper_items(facts, helper_prefix)

      :error ->
        case verified_route_path_prefix(uri, source, position) do
          {:ok, typed_path} ->
            facts
            |> Facts.by_kind(:route)
            |> Enum.map(&route_item/1)
            |> prefixed_items(typed_path)

          :error ->
            []
        end
    end
  end

  defp route_prefix("~p\"" <> path), do: {:ok, path}
  defp route_prefix("~p'" <> path), do: {:ok, path}
  defp route_prefix(_prefix), do: :error

  defp route_helper_prefix("Routes." <> prefix), do: {:ok, prefix}
  defp route_helper_prefix(_prefix), do: :error

  defp verified_route_path_prefix(uri, source, position) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         true <- elixir_source_uri?(uri),
         true <- offset <= byte_size(source),
         source_before_cursor <- binary_part(source, 0, offset) do
      route_sigil_tokenizer_rest(source_before_cursor)
    else
      _not_route_sigil -> :error
    end
  end

  defp elixir_source_uri?(uri) when is_binary(uri), do: not String.ends_with?(uri, ".heex")
  defp elixir_source_uri?(_uri), do: false

  defp route_sigil_tokenizer_rest(source_before_cursor) do
    case :elixir_tokenizer.tokenize(String.to_charlist(source_before_cursor), 1, []) do
      {:error, _reason, rest, _warnings, _tokens} when is_list(rest) ->
        route_prefix_from_sigil_rest(List.to_string(rest))

      _complete_or_unusable ->
        :error
    end
  end

  defp route_prefix_from_sigil_rest("~p\"\"\"" <> path), do: {:ok, path}
  defp route_prefix_from_sigil_rest("~p'''" <> path), do: {:ok, path}
  defp route_prefix_from_sigil_rest("~p\"" <> path), do: {:ok, path}
  defp route_prefix_from_sigil_rest("~p'" <> path), do: {:ok, path}
  defp route_prefix_from_sigil_rest(_rest), do: :error

  defp route_item(fact) do
    path = fact.data.path

    {path,
     %CompletionItem{
       label: path,
       kind: CompletionItemKind.reference(),
       detail: route_detail(fact),
       insert_text: path,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "route", "id" => fact.id}
     }}
  end

  defp route_helper_items(facts, helper_prefix) do
    facts
    |> Facts.by_kind(:route)
    |> route_helper_groups()
    |> Enum.flat_map(&route_helper_group_items/1)
    |> prefixed_items(helper_prefix)
  end

  defp route_helper_groups(route_facts) do
    route_facts
    |> Enum.reject(&blank?(&1.data.helper_base))
    |> Enum.group_by(& &1.data.helper_base)
    |> Enum.sort_by(fn {helper_base, _routes} -> helper_base end)
  end

  defp route_helper_group_items({helper_base, routes}) do
    Enum.map([:path, :url], fn variant ->
      label = RouteHelpers.helper_name(helper_base, variant)

      {label,
       %CompletionItem{
         label: label,
         kind: CompletionItemKind.function(),
         detail: "Routes.#{label}",
         insert_text: helper_snippet(label, routes),
         insert_text_format: InsertTextFormat.snippet(),
         data: %{"kind" => "route_helper", "helper" => label}
       }}
    end)
  end

  defp helper_snippet(helper_name, routes) do
    args =
      ["${1:conn_or_socket}"] ++
        action_snippet_args(routes, 2) ++
        param_snippet_args(routes, 3)

    "#{helper_name}(#{Enum.join(args, ", ")})"
  end

  defp action_snippet_args(routes, placeholder_index) do
    case RouteHelpers.actions(routes) do
      [] -> []
      [action] -> [":${#{placeholder_index}:#{action}}"]
      actions -> [":${#{placeholder_index}|#{Enum.join(actions, ",")}|}"]
    end
  end

  defp param_snippet_args(routes, first_placeholder_index) do
    routes
    |> RouteHelpers.path_parameter_labels()
    |> Enum.with_index(first_placeholder_index)
    |> Enum.map(fn {param, index} -> "${#{index}:#{param}}" end)
  end

  defp route_detail(fact) do
    detail = "#{fact.data.verb} #{fact.data.plug}"

    case fact.data.action do
      nil -> detail
      action -> detail <> " :" <> Atom.to_string(action)
    end
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
