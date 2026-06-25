defmodule PhoenixLS.Features.Completion.Uploads do
  @moduledoc """
  Completion items for LiveView upload names.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.{Facts, TemplateFacts}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(_context, _facts), do: []

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    with uri when is_binary(uri) <- uri,
         {:ok, context} <- CursorContext.at(source, position),
         items when is_list(items) <- complete(uri, source, position, context, facts) do
      items
    else
      _not_scoped_context -> []
    end
  end

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), CursorContext.t(), [
          Fact.t()
        ]) :: [CompletionItem.t()]
  def complete(uri, _source, _position, %CursorContext{} = context, facts)
      when (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    with uri when is_binary(uri) <- uri,
         {:ok, module} <- TemplateFacts.module_for_uri(facts, uri) do
      complete_source_context(context, facts, module)
    else
      _not_scoped_context -> []
    end
  end

  defp complete_source_context(
         %CursorContext{kind: :expression, prefix: "@uploads." <> prefix},
         facts,
         module
       ) do
    facts
    |> Facts.by_kind(:upload)
    |> Enum.filter(&(&1.data.module == module))
    |> Enum.map(&upload_item/1)
    |> Enum.filter(fn {label, _item} -> String.starts_with?(label, prefix) end)
    |> Enum.map(fn {_label, item} -> item end)
  end

  defp complete_source_context(_context, _facts, _module), do: []

  defp upload_item(%Fact{} = fact) do
    label = fact.data.name

    {label,
     %CompletionItem{
       label: label,
       kind: CompletionItemKind.property(),
       detail: "LiveView upload :#{label}",
       insert_text: label,
       insert_text_format: InsertTextFormat.plain_text(),
       data: %{"kind" => "upload", "id" => fact.id}
     }}
  end
end
