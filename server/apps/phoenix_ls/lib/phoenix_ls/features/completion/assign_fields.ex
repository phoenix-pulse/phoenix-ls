defmodule PhoenixLS.Features.Completion.AssignFields do
  @moduledoc """
  Schema-backed field completions for assign property access.
  """

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.AssignAccess
  alias PhoenixLS.Features.Completion.{SchemaFacts, Schemas}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) when is_binary(prefix) do
    with {:ok, assign, path, field_prefix} <- AssignAccess.field_access(prefix),
         {:ok, base_schema_id} <- SchemaFacts.schema_id_for_assign(assign, facts),
         {:ok, schema_id} <- schema_id_for_path(base_schema_id, path, facts) do
      Schemas.property_items(facts, field_prefix, schema_id)
    else
      _not_assign_field -> []
    end
  end

  def complete(_context, _facts), do: []

  defp schema_id_for_path(schema_id, [], _facts), do: {:ok, schema_id}

  defp schema_id_for_path(schema_id, path, facts) do
    SchemaFacts.schema_id_for_association_path(schema_id, path, facts)
  end
end
