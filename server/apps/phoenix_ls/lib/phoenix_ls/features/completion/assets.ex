defmodule PhoenixLS.Features.Completion.Assets do
  @moduledoc """
  Completion items for static assets in verified `~p` paths.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext

  @static_prefixes ["/images/", "/css/", "/js/", "/fonts/", "/assets/"]

  @spec complete(CursorContext.t(), [PhoenixLS.Index.Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) do
    case asset_prefix(prefix) do
      {:ok, typed_path} ->
        facts
        |> Enum.filter(&(&1.kind == :asset))
        |> Enum.map(&asset_item/1)
        |> prefixed_items(typed_path)

      :error ->
        []
    end
  end

  def complete(_context, _facts), do: []

  defp asset_prefix("~p\"" <> path), do: static_asset_prefix(path)
  defp asset_prefix("~p'" <> path), do: static_asset_prefix(path)
  defp asset_prefix(_prefix), do: :error

  defp static_asset_prefix(path) do
    if Enum.any?(@static_prefixes, &String.starts_with?(path, &1)) do
      {:ok, path}
    else
      :error
    end
  end

  defp asset_item(fact) do
    public_path = fact.data.public_path

    {public_path,
     %CompletionItem{
       label: public_path,
       kind: CompletionItemKind.file(),
       detail: "#{fact.data.type} asset - #{format_size(fact.data.size)} KB",
       insert_text: public_path,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "asset", "id" => fact.id}
     }}
  end

  defp format_size(size) when is_integer(size) and size >= 0 do
    :erlang.float_to_binary(size / 1024, decimals: 1)
  end

  defp prefixed_items(items, prefix) do
    items
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix || "") end)
    |> Enum.sort_by(fn {label, _item} -> label end)
    |> Enum.map(fn {_label, item} -> item end)
  end
end
