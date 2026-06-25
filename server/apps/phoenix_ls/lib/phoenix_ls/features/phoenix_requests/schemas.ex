defmodule PhoenixLS.Features.PhoenixRequests.Schemas do
  @moduledoc """
  Payload builder for schema explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @spec list(term()) :: [map()]
  def list(facts) do
    fields_by_schema =
      facts
      |> Payload.facts_by_kind(:schema_field)
      |> Enum.group_by(& &1.data.schema)

    associations_by_schema =
      facts
      |> Payload.facts_by_kind(:schema_association)
      |> Enum.group_by(& &1.data.schema)

    facts
    |> Payload.facts_by_kind(:schema)
    |> Enum.map(fn fact ->
      associations = Map.get(associations_by_schema, fact.id, [])
      fields = Map.get(fields_by_schema, fact.id, [])
      field_payloads = schema_field_payloads(fact, fields, associations)

      %{
        "id" => fact.id,
        "name" => fact.data.module,
        "module" => fact.data.module,
        "source" => fact.data.source,
        "table" => fact.data.source,
        "tableName" => fact.data.source,
        "filePath" => Payload.file_path(fact.uri),
        "location" => Payload.location(fact),
        "fieldsCount" => length(field_payloads),
        "associationsCount" => length(associations),
        "fields" => field_payloads,
        "associations" => Enum.map(associations, &schema_association_payload/1)
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp schema_field_payloads(schema_fact, fields, associations) do
    association_foreign_keys = association_foreign_keys(associations)
    explicit_field_names = MapSet.new(fields, & &1.data.name)

    generated_primary_key_payloads(schema_fact, explicit_field_names) ++
      Enum.map(fields, &schema_field_payload(&1, schema_fact, association_foreign_keys)) ++
      generated_association_field_payloads(
        schema_fact,
        associations,
        explicit_field_names
      )
  end

  defp schema_field_payload(fact, schema_fact, association_foreign_keys) do
    primary_key_name = primary_key_name(schema_fact)
    reference = Map.get(association_foreign_keys, fact.data.name)

    %{
      "name" => fact.data.name,
      "type" => Payload.type_string(fact.data.type),
      "elixirType" => inspect(fact.data.type),
      "primaryKey" => fact.data.name == primary_key_name,
      "foreignKey" => not is_nil(reference),
      "generated" => generated_field?(fact),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
    |> Payload.maybe_put("references", reference)
  end

  defp generated_primary_key_payloads(%Fact{data: %{primary_key: false}}, _explicit_field_names),
    do: []

  defp generated_primary_key_payloads(%Fact{} = schema_fact, explicit_field_names) do
    primary_key = schema_fact.data.primary_key

    if MapSet.member?(explicit_field_names, primary_key.name) do
      []
    else
      [
        %{
          "name" => primary_key.name,
          "type" => Payload.type_string(primary_key.type),
          "elixirType" => inspect(primary_key.type),
          "primaryKey" => true,
          "foreignKey" => false,
          "generated" => true,
          "filePath" => Payload.file_path(schema_fact.uri),
          "location" => Payload.location(schema_fact)
        }
      ]
    end
  end

  defp generated_association_field_payloads(schema_fact, associations, explicit_field_names) do
    associations
    |> Enum.filter(&(&1.data.association == :belongs_to))
    |> Enum.filter(&association_defines_field?/1)
    |> Enum.reject(&MapSet.member?(explicit_field_names, association_foreign_key(&1)))
    |> Enum.map(fn association ->
      type = association_type(association, schema_fact)
      name = association_foreign_key(association)

      %{
        "name" => name,
        "type" => Payload.type_string(type),
        "elixirType" => inspect(type),
        "primaryKey" => false,
        "foreignKey" => true,
        "generated" => true,
        "references" => association.data.related,
        "filePath" => Payload.file_path(association.uri),
        "location" => Payload.location(association)
      }
    end)
  end

  defp association_foreign_keys(associations) do
    associations
    |> Enum.filter(&(&1.data.association == :belongs_to))
    |> Map.new(fn association ->
      {association_foreign_key(association), association.data.related}
    end)
  end

  defp primary_key_name(%Fact{data: %{primary_key: false}}), do: nil
  defp primary_key_name(%Fact{data: %{primary_key: primary_key}}), do: primary_key.name

  defp generated_field?(%Fact{data: %{options: options}}) do
    Keyword.has_key?(options || [], :generated_by)
  end

  defp association_foreign_key(%Fact{data: %{name: name, options: options}}) do
    options
    |> Keyword.get(:foreign_key, :"#{name}_id")
    |> Atom.to_string()
  end

  defp association_type(%Fact{data: %{options: options}}, schema_fact) do
    Keyword.get(options || [], :type, schema_fact.data.foreign_key_type)
  end

  defp association_defines_field?(%Fact{data: %{options: options}}) do
    Keyword.get(options || [], :define_field, true) != false
  end

  defp schema_association_payload(fact) do
    fact.data.options
    |> Payload.association_option_payload()
    |> Map.merge(%{
      "name" => fact.data.name,
      "fieldName" => fact.data.name,
      "foreignKey" => association_foreign_key(fact),
      "schema" => fact.data.related,
      "targetModule" => fact.data.related,
      "type" => Atom.to_string(fact.data.association),
      "cardinality" => association_cardinality(fact.data.association),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    })
  end

  defp association_cardinality(:belongs_to), do: "many_to_one"
  defp association_cardinality(:has_one), do: "one_to_one"
  defp association_cardinality(:has_many), do: "one_to_many"
  defp association_cardinality(:many_to_many), do: "many_to_many"
  defp association_cardinality(:embeds_one), do: "one_to_one"
  defp association_cardinality(:embeds_many), do: "one_to_many"
  defp association_cardinality(_association), do: "unknown"
end
