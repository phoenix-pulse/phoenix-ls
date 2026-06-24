defmodule PhoenixLS.Introspection.Schema do
  @moduledoc """
  Source-only extraction helpers for Ecto schema facts.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  defmodule Schema do
    @moduledoc """
    Typed Ecto schema fact payload.
    """

    @enforce_keys [:module, :source]
    defstruct [:module, :source]
  end

  defmodule Field do
    @moduledoc """
    Typed Ecto schema field fact payload.
    """

    @enforce_keys [:schema, :module, :name, :type, :options]
    defstruct [:schema, :module, :name, :type, :options]
  end

  defmodule Association do
    @moduledoc """
    Typed Ecto schema association fact payload.
    """

    @enforce_keys [:schema, :module, :name, :association, :related, :options]
    defstruct [:schema, :module, :name, :association, :related, :options]
  end

  @association_macros [:belongs_to, :has_many, :has_one, :many_to_many]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> top_level_expressions()
    |> Enum.flat_map(&collect_expression(&1, module, uri, provenance))
  end

  defp collect_expression({:schema, meta, [source, [do: block]]}, module, uri, provenance)
       when is_binary(source) do
    schema_id = "#{module}:schema:#{source}"

    schema_fact =
      Fact.new!(
        kind: :schema,
        id: schema_id,
        uri: uri,
        range: source_range(meta),
        provenance: provenance,
        data: %Schema{
          module: module,
          source: source
        }
      )

    [schema_fact | schema_detail_facts(schema_id, module, block, uri, provenance)]
  end

  defp collect_expression(_expression, _module, _uri, _provenance), do: []

  defp schema_detail_facts(schema_id, module, block, uri, provenance) do
    block
    |> top_level_expressions()
    |> Enum.flat_map(fn
      {:field, meta, args} ->
        case field_fact(schema_id, module, meta, args, uri, provenance) do
          {:ok, fact} -> [fact]
          :error -> []
        end

      {association, meta, args} when association in @association_macros ->
        case association_fact(schema_id, module, association, meta, args, uri, provenance) do
          {:ok, fact} -> [fact]
          :error -> []
        end

      _other ->
        []
    end)
  end

  defp field_fact(schema_id, module, meta, [name, type], uri, provenance) when is_atom(name) do
    field_fact(schema_id, module, meta, [name, type, []], uri, provenance)
  end

  defp field_fact(schema_id, module, meta, [name, type, options], uri, provenance)
       when is_atom(name) and is_list(options) do
    name = Atom.to_string(name)

    {:ok,
     Fact.new!(
       kind: :schema_field,
       id: "#{schema_id}:field:#{name}",
       uri: uri,
       range: source_range(meta),
       provenance: provenance,
       data: %Field{
         schema: schema_id,
         module: module,
         name: name,
         type: type,
         options: options
       }
     )}
  end

  defp field_fact(_schema_id, _module, _meta, _args, _uri, _provenance), do: :error

  defp association_fact(schema_id, module, association, meta, [name, related], uri, provenance)
       when is_atom(name) do
    association_fact(schema_id, module, association, meta, [name, related, []], uri, provenance)
  end

  defp association_fact(
         schema_id,
         module,
         association,
         meta,
         [name, related, options],
         uri,
         provenance
       )
       when is_atom(name) and is_list(options) do
    with {:ok, related_module} <- alias_to_string(related) do
      name = Atom.to_string(name)

      {:ok,
       Fact.new!(
         kind: :schema_association,
         id: "#{schema_id}:association:#{name}",
         uri: uri,
         range: source_range(meta),
         provenance: provenance,
         data: %Association{
           schema: schema_id,
           module: module,
           name: name,
           association: association,
           related: related_module,
           options: options
         }
       )}
    end
  end

  defp association_fact(_schema_id, _module, _association, _meta, _args, _uri, _provenance),
    do: :error

  defp alias_to_string({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1) do
      {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
    else
      :error
    end
  end

  defp alias_to_string(atom) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  defp alias_to_string(_ast), do: :error

  defp top_level_expressions({:__block__, _meta, expressions}), do: expressions
  defp top_level_expressions(nil), do: []
  defp top_level_expressions(expression), do: [expression]

  defp source_range(meta) do
    %Range{
      start: position(meta),
      end: position(end_meta(meta))
    }
  end

  defp end_meta(meta) do
    Keyword.get(meta, :end_of_expression) || Keyword.get(meta, :end) || meta
  end

  defp position(meta) do
    %Position{
      line: meta |> Keyword.get(:line, 1) |> zero_based(),
      character: meta |> Keyword.get(:column, 1) |> zero_based()
    }
  end

  defp zero_based(value) when is_integer(value) and value > 0, do: value - 1
  defp zero_based(_value), do: 0
end
