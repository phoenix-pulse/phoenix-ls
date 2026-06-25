defmodule PhoenixLS.Introspection.Changeset do
  @moduledoc """
  Source-only extraction of exact Ecto changeset validation facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source

  defmodule Validation do
    @moduledoc """
    Typed changeset validation fact payload.
    """

    @enforce_keys [:module, :field, :validation, :options, :confidence]
    defstruct [:module, :field, :validation, :options, :confidence]
  end

  @validation_macros [:validate_required, :validate_length, :validate_number, :unique_constraint]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> validation_entries()
    |> Enum.map(fn %{range: range, validation: validation, field: field, options: options} ->
      Fact.new!(
        kind: :changeset_validation,
        id:
          "#{module}:changeset:#{validation}:#{field}:#{range.start.line}:#{range.start.character}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Validation{
          module: module,
          field: field,
          validation: validation,
          options: options,
          confidence: :exact
        }
      )
    end)
  end

  defp validation_entries(ast) do
    ast
    |> collect_nodes()
    |> Enum.flat_map(&validation_entry/1)
  end

  defp validation_entry({validation, meta, args})
       when validation in @validation_macros and is_list(args) do
    validation
    |> validation_fields(args)
    |> Enum.map(fn {field, options} ->
      %{
        range: Source.source_range(meta),
        validation: validation,
        field: field,
        options: options
      }
    end)
  end

  defp validation_entry(_node), do: []

  defp validation_fields(:validate_required, [fields | _rest]) do
    fields
    |> static_field_names()
    |> Enum.map(&{&1, []})
  end

  defp validation_fields(:validate_length, [field | rest]) do
    single_field_with_options(field, rest)
  end

  defp validation_fields(:validate_number, [field | rest]) do
    single_field_with_options(field, rest)
  end

  defp validation_fields(:unique_constraint, [field | rest]) do
    single_field_with_options(field, rest)
  end

  defp validation_fields(_validation, _args), do: []

  defp single_field_with_options(field, rest) do
    case static_field_names(field) do
      [name] -> [{name, validation_options(rest)}]
      _not_static -> []
    end
  end

  defp validation_options([options | _rest]) when is_list(options) do
    if Keyword.keyword?(options), do: options, else: []
  end

  defp validation_options(_rest), do: []

  defp static_field_names(field) when is_atom(field), do: [Atom.to_string(field)]

  defp static_field_names(fields) when is_list(fields) do
    Enum.flat_map(fields, &static_field_names/1)
  end

  defp static_field_names(_field), do: []

  defp collect_nodes(ast) do
    {_ast, nodes} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, [node | acc]}
      end)

    Enum.reverse(nodes)
  end
end
