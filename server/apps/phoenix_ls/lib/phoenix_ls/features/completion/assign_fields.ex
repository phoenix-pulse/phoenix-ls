defmodule PhoenixLS.Features.Completion.AssignFields do
  @moduledoc """
  Schema-backed field completions for assign property access.
  """

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.{SchemaFacts, Schemas}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec complete(CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(%CursorContext{kind: :expression, prefix: prefix}, facts) when is_binary(prefix) do
    with {:ok, assign, path, field_prefix} <- assign_field_prefix(prefix),
         {:ok, base_schema_id} <- SchemaFacts.schema_id_for_assign(assign, facts),
         {:ok, schema_id} <- schema_id_for_path(base_schema_id, path, facts) do
      Schemas.field_items(facts, field_prefix, schema_id)
    else
      _not_assign_field -> []
    end
  end

  def complete(_context, _facts), do: []

  defp assign_field_prefix("@" <> rest), do: split_assign_field(rest)
  defp assign_field_prefix("assigns." <> rest), do: split_assign_field(rest)
  defp assign_field_prefix(_prefix), do: :error

  defp split_assign_field(rest) do
    case String.split(rest, ".") do
      [assign, field_prefix] ->
        validate_parts(assign, [], field_prefix)

      [assign | [_path_segment | _rest] = path_and_field] ->
        {path, [field_prefix]} = Enum.split(path_and_field, -1)
        validate_parts(assign, path, field_prefix)

      _other ->
        :error
    end
  end

  defp validate_parts(assign, path, field_prefix) do
    if SchemaFacts.identifier?(assign) and Enum.all?(path, &SchemaFacts.identifier?/1) do
      {:ok, assign, path, field_prefix || ""}
    else
      :error
    end
  end

  defp schema_id_for_path(schema_id, [], _facts), do: {:ok, schema_id}

  defp schema_id_for_path(schema_id, path, facts) do
    SchemaFacts.schema_id_for_association_path(schema_id, path, facts)
  end
end
