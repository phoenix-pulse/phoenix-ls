defmodule PhoenixLS.Features.Completion.SchemaFacts do
  @moduledoc """
  Schema fact lookup helpers shared by Phoenix completion providers.
  """

  alias PhoenixLS.Index.Fact

  @spec schema_id_for_source(String.t(), [Fact.t()]) :: {:ok, String.t()} | :error
  def schema_id_for_source(source, facts) when is_binary(source) and is_list(facts) do
    case String.trim(source) do
      "@" <> assign -> schema_id_for_assign(assign, facts)
      ":" <> atom -> schema_id_for_name(atom, facts)
      _source -> :error
    end
  end

  @spec schema_id_for_assign(String.t(), [Fact.t()]) :: {:ok, String.t()} | :error
  def schema_id_for_assign(assign, facts) when is_binary(assign) and is_list(facts) do
    assign
    |> candidate_names()
    |> Enum.find_value(:error, fn name ->
      case schema_id_for_name(name, facts) do
        {:ok, schema_id} -> {:ok, schema_id}
        :error -> false
      end
    end)
  end

  @spec schema_for_assign_prefix(String.t(), [Fact.t()]) :: Fact.t() | nil
  def schema_for_assign_prefix(assign_prefix, facts)
      when is_binary(assign_prefix) and is_list(facts) do
    candidates = candidate_schema_prefixes(assign_prefix)

    Enum.find(
      facts,
      &(&1.kind == :schema and schema_prefix_match?(&1, candidates))
    )
  end

  @spec schema_id_for_association_path(String.t(), [String.t()], [Fact.t()]) ::
          {:ok, String.t()} | :error
  def schema_id_for_association_path(schema_id, path, facts)
      when is_binary(schema_id) and is_list(path) and is_list(facts) do
    Enum.reduce_while(path, {:ok, schema_id}, fn segment, {:ok, current_schema_id} ->
      case schema_id_for_association(current_schema_id, segment, facts) do
        {:ok, next_schema_id} -> {:cont, {:ok, next_schema_id}}
        :error -> {:halt, :error}
      end
    end)
  end

  @spec schema_fields(String.t(), [Fact.t()]) :: [Fact.t()]
  def schema_fields(schema_id, facts) when is_binary(schema_id) and is_list(facts) do
    Enum.filter(facts, &schema_field?(&1, schema_id))
  end

  @spec schema_associations(String.t(), [Fact.t()]) :: [Fact.t()]
  def schema_associations(schema_id, facts) when is_binary(schema_id) and is_list(facts) do
    Enum.filter(facts, &schema_association?(&1, schema_id))
  end

  @spec schema_properties(String.t(), [Fact.t()]) :: [Fact.t()]
  def schema_properties(schema_id, facts) when is_binary(schema_id) and is_list(facts) do
    schema_fields(schema_id, facts) ++ schema_associations(schema_id, facts)
  end

  @spec schema_property(String.t(), String.t(), [Fact.t()]) :: Fact.t() | nil
  def schema_property(schema_id, prefix, facts)
      when is_binary(schema_id) and is_binary(prefix) and is_list(facts) do
    properties = schema_properties(schema_id, facts)

    Enum.find(properties, &(fact_name(&1) == prefix)) ||
      Enum.find(properties, &String.starts_with?(fact_name(&1), prefix))
  end

  @spec identifier?(String.t()) :: boolean()
  def identifier?(<<first::utf8, rest::binary>>) do
    identifier_start?(first) and rest_identifier?(rest)
  end

  def identifier?(_value), do: false

  defp schema_id_for_name(name, facts) do
    with {:ok, candidate} <- camelized_candidate(name) do
      facts
      |> Enum.filter(&(&1.kind == :schema))
      |> Enum.find(&schema_match?(&1, candidate))
      |> case do
        %Fact{id: schema_id} -> {:ok, schema_id}
        nil -> :error
      end
    end
  end

  defp schema_id_for_association(schema_id, name, facts) do
    with %Fact{data: %{related: related_module}} <-
           Enum.find(facts, &association_fact?(&1, schema_id, name)),
         %Fact{id: related_schema_id} <- Enum.find(facts, &schema_for_module?(&1, related_module)) do
      {:ok, related_schema_id}
    else
      _missing_association -> :error
    end
  end

  defp schema_field?(%Fact{kind: :schema_field, data: data}, schema_id),
    do: data.schema == schema_id

  defp schema_field?(_fact, _schema_id), do: false

  defp schema_association?(%Fact{kind: :schema_association, data: data}, schema_id),
    do: data.schema == schema_id

  defp schema_association?(_fact, _schema_id), do: false

  defp fact_name(%Fact{data: %{name: name}}), do: name

  defp association_fact?(%Fact{kind: :schema_association, data: data}, schema_id, name) do
    data.schema == schema_id and data.name == name
  end

  defp association_fact?(_fact, _schema_id, _name), do: false

  defp schema_for_module?(%Fact{kind: :schema, data: %{module: fact_module}}, module)
       when fact_module == module,
       do: true

  defp schema_for_module?(_fact, _module), do: false

  defp schema_match?(%Fact{data: %{module: module}}, candidate) do
    module == candidate or String.ends_with?(module, "." <> candidate)
  end

  defp schema_prefix_match?(_fact, []), do: false

  defp schema_prefix_match?(%Fact{data: %{module: module}}, candidates) do
    local_name =
      module
      |> String.split(".")
      |> List.last()

    Enum.any?(candidates, &String.starts_with?(local_name, &1))
  end

  defp candidate_schema_prefixes(assign_prefix) do
    assign_prefix
    |> candidate_names()
    |> Enum.flat_map(fn name ->
      case camelized_candidate(name) do
        {:ok, candidate} -> [candidate]
        :error -> []
      end
    end)
  end

  defp candidate_names(name) do
    [name, singular_name(name)]
    |> Enum.uniq()
    |> Enum.filter(&identifier?/1)
  end

  defp singular_name(name) do
    cond do
      String.ends_with?(name, "ies") and byte_size(name) > 3 ->
        String.replace_suffix(name, "ies", "y")

      String.ends_with?(name, "s") and byte_size(name) > 1 ->
        String.replace_suffix(name, "s", "")

      true ->
        name
    end
  end

  defp camelized_candidate(value) do
    if identifier?(value) do
      {:ok,
       value
       |> String.split("_")
       |> Enum.map_join("", &String.capitalize/1)}
    else
      :error
    end
  end

  defp rest_identifier?(<<char::utf8, rest::binary>>) do
    identifier_char?(char) and rest_identifier?(rest)
  end

  defp rest_identifier?(""), do: true

  defp identifier_start?(char), do: char == ?_ or lower?(char) or upper?(char)
  defp identifier_char?(char), do: identifier_start?(char) or digit?(char)

  defp lower?(char), do: char >= ?a and char <= ?z
  defp upper?(char), do: char >= ?A and char <= ?Z
  defp digit?(char), do: char >= ?0 and char <= ?9
end
