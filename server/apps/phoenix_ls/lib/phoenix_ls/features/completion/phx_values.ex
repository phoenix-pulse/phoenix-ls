defmodule PhoenixLS.Features.Completion.PhxValues do
  @moduledoc """
  Context-aware `phx-value-*` completions for schema-backed `:for` loops.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.SchemaFacts
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.HEEx.Scope.Variable
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      complete(source, position, context, facts)
    else
      _not_phx_value_context -> []
    end
  end

  @spec complete(String.t(), Positions.lsp_position(), CursorContext.t(), [Fact.t()]) :: [
          CompletionItem.t()
        ]
  def complete(
        source,
        position,
        %CursorContext{kind: :attribute_name, prefix: "phx-value-" <> prefix},
        facts
      )
      when is_binary(source) and is_list(facts) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source),
         {:ok, binding, schema_id} <-
           enclosing_schema_binding(document.tags, source, offset, facts) do
      schema_id
      |> SchemaFacts.schema_fields(facts)
      |> Enum.filter(&String.starts_with?(&1.data.name, prefix))
      |> Enum.map(&field_item(&1, binding.name))
    else
      _not_phx_value_context -> []
    end
  end

  def complete(_source, _position, %CursorContext{}, _facts), do: []

  defp enclosing_schema_binding(tags, source, offset, facts) do
    tags
    |> Scope.scoped_variables(source, offset)
    |> Enum.reverse()
    |> Enum.reduce_while(:error, fn
      %Variable{kind: :for} = binding, _acc ->
        case schema_id_for_binding(binding, facts) do
          {:ok, schema_id} -> {:halt, {:ok, binding, schema_id}}
          :error -> {:cont, :error}
        end

      %Variable{}, _acc ->
        {:cont, :error}
    end)
  end

  defp schema_id_for_binding(%Variable{source: {:assign, assign, []}}, facts) do
    SchemaFacts.schema_id_for_assign(assign, facts)
  end

  defp schema_id_for_binding(%Variable{source: {:assign, assign, path}}, facts) do
    with {:ok, base_schema_id} <- SchemaFacts.schema_id_for_assign(assign, facts) do
      SchemaFacts.schema_id_for_association_path(base_schema_id, path, facts)
    end
  end

  defp schema_id_for_binding(%Variable{}, _facts), do: :error

  defp field_item(%Fact{} = fact, variable) do
    field = fact.data.name

    %CompletionItem{
      label: "phx-value-#{field}",
      kind: CompletionItemKind.property(),
      detail: "From #{variable}: #{inspect(fact.data.type)}",
      insert_text: "phx-value-#{field}={#{variable}.#{field}}",
      insert_text_format: InsertTextFormat.plain_text(),
      data: %{"kind" => "phx_value_field", "id" => fact.id}
    }
  end
end
