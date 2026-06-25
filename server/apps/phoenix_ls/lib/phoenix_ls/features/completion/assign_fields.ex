defmodule PhoenixLS.Features.Completion.AssignFields do
  @moduledoc """
  Schema-backed field completions for assign property access.
  """

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.{AssignAccess, ControllerTemplate}
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

  @spec complete(String.t() | nil, CursorContext.t(), [Fact.t()]) :: [CompletionItem.t()]
  def complete(uri, %CursorContext{kind: :expression, prefix: prefix} = context, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(prefix) and is_list(facts) do
    with uri when is_binary(uri) <- uri,
         {:ok, assign, path, field_prefix} <- AssignAccess.field_access(prefix),
         {:ok, base_schema_id} <- controller_schema_id_for_assign(uri, assign, facts),
         {:ok, schema_id} <- schema_id_for_path(base_schema_id, path, facts) do
      Schemas.property_items(facts, field_prefix, schema_id)
    else
      _not_controller_assign_field -> complete(context, facts)
    end
  end

  def complete(_uri, context, facts), do: complete(context, facts)

  defp controller_schema_id_for_assign(uri, assign, facts) do
    with %Fact{data: %{schema_source: schema_source}} when is_binary(schema_source) <-
           ControllerTemplate.assign_fact(facts, uri, assign) do
      SchemaFacts.schema_id_for_assign(schema_source, facts)
    else
      _missing_controller_schema -> :error
    end
  end

  defp schema_id_for_path(schema_id, [], _facts), do: {:ok, schema_id}

  defp schema_id_for_path(schema_id, path, facts) do
    SchemaFacts.schema_id_for_association_path(schema_id, path, facts)
  end
end
