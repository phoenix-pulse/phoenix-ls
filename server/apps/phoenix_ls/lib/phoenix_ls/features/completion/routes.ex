defmodule PhoenixLS.Features.Completion.Routes do
  @moduledoc """
  Completion items for verified `~p` route paths.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
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
        |> facts_by_kind(:route)
        |> Enum.map(&route_item/1)
        |> prefixed_items(typed_path)

      :error ->
        []
    end
  end

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    case elixir_route_helper_prefix(source, position) do
      {:ok, helper_prefix} -> route_helper_items(facts, helper_prefix)
      :error -> []
    end
  end

  defp route_prefix("~p\"" <> path), do: {:ok, path}
  defp route_prefix("~p'" <> path), do: {:ok, path}
  defp route_prefix(_prefix), do: :error

  defp route_helper_prefix("Routes." <> prefix), do: {:ok, prefix}
  defp route_helper_prefix(_prefix), do: :error

  defp elixir_route_helper_prefix(source, position) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, source_before_cursor} <- source_before_cursor(source, offset),
         {:ok, tokens} <- tokenize(source_before_cursor) do
      route_helper_prefix_from_tokens(tokens)
    end
  end

  defp source_before_cursor(source, offset) when offset <= byte_size(source) do
    {:ok, binary_part(source, 0, offset)}
  end

  defp source_before_cursor(_source, _offset), do: :error

  defp tokenize(source) do
    case :elixir_tokenizer.tokenize(String.to_charlist(source), 1, []) do
      {:ok, _line, _column, _warnings, tokens, _comments} -> {:ok, tokens}
      {:error, _reason, _line, _column, _warnings, _tokens} -> :error
      {:error, _reason, _rest, _warnings, _tokens} -> :error
      _unexpected -> :error
    end
  end

  defp route_helper_prefix_from_tokens([
         {:identifier, _identifier_meta, helper_prefix},
         {:., _dot_meta},
         {:alias, _alias_meta, :Routes}
         | _rest
       ]) do
    {:ok, Atom.to_string(helper_prefix)}
  end

  defp route_helper_prefix_from_tokens([
         {:., _dot_meta},
         {:alias, _alias_meta, :Routes}
         | _rest
       ]) do
    {:ok, ""}
  end

  defp route_helper_prefix_from_tokens(_tokens), do: :error

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
    |> facts_by_kind(:route)
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
    Enum.map(["path", "url"], fn variant ->
      label = "#{helper_base}_#{variant}"

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
    actions =
      routes
      |> Enum.map(& &1.data.action)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Atom.to_string/1)
      |> Enum.uniq()
      |> Enum.sort()

    case actions do
      [] -> []
      [action] -> [":${#{placeholder_index}:#{action}}"]
      actions -> [":${#{placeholder_index}|#{Enum.join(actions, ",")}|}"]
    end
  end

  defp param_snippet_args(routes, first_placeholder_index) do
    routes
    |> Enum.flat_map(& &1.data.path_params)
    |> Enum.uniq()
    |> Enum.sort()
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

  defp facts_by_kind(facts, kind) do
    Enum.filter(facts, &(&1.kind == kind))
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
