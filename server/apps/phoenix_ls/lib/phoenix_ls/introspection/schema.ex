defmodule PhoenixLS.Introspection.Schema do
  @moduledoc """
  Source-only extraction helpers for Ecto schema facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source

  defmodule PrimaryKey do
    @moduledoc """
    Typed Ecto primary key configuration carried by schema facts.
    """

    @enforce_keys [:name, :type, :options]
    defstruct [:name, :type, :options]
  end

  defmodule Schema do
    @moduledoc """
    Typed Ecto schema fact payload.
    """

    @enforce_keys [:module, :source, :primary_key, :foreign_key_type]
    defstruct [:module, :source, :primary_key, :foreign_key_type]
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

  @association_macros [:belongs_to, :has_many, :has_one, :many_to_many, :embeds_one, :embeds_many]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    expressions = Source.top_level_expressions(body_ast)
    aliases = aliases(expressions)

    expressions
    |> Enum.reduce(%{facts: [], config: default_schema_config()}, fn expression, state ->
      case schema_config(expression, state.config) do
        {:ok, config} ->
          %{state | config: config}

        :none ->
          facts = collect_expression(expression, module, uri, provenance, aliases, state.config)
          %{state | facts: state.facts ++ facts}
      end
    end)
    |> Map.fetch!(:facts)
  end

  defp collect_expression(
         {:schema, meta, [source, [do: block]]},
         module,
         uri,
         provenance,
         aliases,
         config
       )
       when is_binary(source) do
    schema_id = schema_id(module, source)

    schema_fact =
      Fact.new!(
        kind: :schema,
        id: schema_id,
        uri: uri,
        range: Source.source_range(meta),
        provenance: provenance,
        data: %Schema{
          module: module,
          source: source,
          primary_key: config.primary_key,
          foreign_key_type: config.foreign_key_type
        }
      )

    [schema_fact | schema_detail_facts(schema_id, module, block, uri, provenance, aliases)]
  end

  defp collect_expression(
         {:embedded_schema, meta, [[do: block]]},
         module,
         uri,
         provenance,
         aliases,
         config
       ) do
    schema_id = schema_id(module, nil)

    schema_fact =
      Fact.new!(
        kind: :schema,
        id: schema_id,
        uri: uri,
        range: Source.source_range(meta),
        provenance: provenance,
        data: %Schema{
          module: module,
          source: nil,
          primary_key: config.primary_key,
          foreign_key_type: config.foreign_key_type
        }
      )

    [schema_fact | schema_detail_facts(schema_id, module, block, uri, provenance, aliases)]
  end

  defp collect_expression(_expression, _module, _uri, _provenance, _aliases, _config), do: []

  defp default_schema_config do
    %{
      primary_key: %PrimaryKey{name: "id", type: :id, options: [autogenerate: true]},
      foreign_key_type: :id
    }
  end

  defp schema_config({:@, _meta, [{:primary_key, _attr_meta, [false]}]}, config) do
    {:ok, %{config | primary_key: false}}
  end

  defp schema_config({:@, _meta, [{:primary_key, _attr_meta, [primary_key_ast]}]}, config) do
    case primary_key(primary_key_ast) do
      {:ok, primary_key} -> {:ok, %{config | primary_key: primary_key}}
      :error -> :none
    end
  end

  defp schema_config({:@, _meta, [{:foreign_key_type, _attr_meta, [type]}]}, config)
       when is_atom(type) do
    {:ok, %{config | foreign_key_type: type}}
  end

  defp schema_config(_expression, _config), do: :none

  defp primary_key({:{}, _meta, [name, type, options]})
       when is_atom(name) and is_atom(type) and is_list(options) do
    {:ok, %PrimaryKey{name: Atom.to_string(name), type: type, options: options}}
  end

  defp primary_key({:{}, _meta, [name, type]}) when is_atom(name) and is_atom(type) do
    {:ok, %PrimaryKey{name: Atom.to_string(name), type: type, options: []}}
  end

  defp primary_key(_ast), do: :error

  defp schema_detail_facts(schema_id, module, block, uri, provenance, aliases) do
    block
    |> Source.top_level_expressions()
    |> Enum.flat_map(fn
      {:field, meta, args} ->
        case field_fact(schema_id, module, meta, args, uri, provenance) do
          {:ok, fact} -> [fact]
          :error -> []
        end

      {association, meta, args} when association in @association_macros ->
        case association_fact(
               schema_id,
               module,
               association,
               meta,
               args,
               uri,
               provenance,
               aliases
             ) do
          {:ok, fact} -> [fact]
          :error -> []
        end

      {:timestamps, meta, args} ->
        timestamp_field_facts(schema_id, module, meta, args, uri, provenance)

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
       range: Source.source_range(meta),
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

  defp timestamp_field_facts(schema_id, module, meta, args, uri, provenance) do
    options = timestamp_options(args)
    type = Keyword.get(options, :type, :naive_datetime)

    Enum.map(["inserted_at", "updated_at"], fn name ->
      timestamp_field_fact(schema_id, module, name, type, meta, options, uri, provenance)
    end)
  end

  defp timestamp_options([]), do: []
  defp timestamp_options([options]) when is_list(options), do: options
  defp timestamp_options(_args), do: []

  defp timestamp_field_fact(schema_id, module, name, type, meta, options, uri, provenance) do
    Fact.new!(
      kind: :schema_field,
      id: "#{schema_id}:field:#{name}",
      uri: uri,
      range: Source.source_range(meta),
      provenance: provenance,
      data: %Field{
        schema: schema_id,
        module: module,
        name: name,
        type: type,
        options: Keyword.put(options, :generated_by, :timestamps)
      }
    )
  end

  defp association_fact(
         schema_id,
         module,
         association,
         meta,
         [name, related],
         uri,
         provenance,
         aliases
       )
       when is_atom(name) do
    association_fact(
      schema_id,
      module,
      association,
      meta,
      [name, related, []],
      uri,
      provenance,
      aliases
    )
  end

  defp association_fact(
         schema_id,
         module,
         association,
         meta,
         [name, related, options],
         uri,
         provenance,
         aliases
       )
       when is_atom(name) and is_list(options) do
    with {:ok, related_module} <- resolve_related(related, module, association, aliases) do
      name = Atom.to_string(name)

      {:ok,
       Fact.new!(
         kind: :schema_association,
         id: "#{schema_id}:association:#{name}",
         uri: uri,
         range: Source.source_range(meta),
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

  defp association_fact(
         _schema_id,
         _module,
         _association,
         _meta,
         _args,
         _uri,
         _provenance,
         _aliases
       ),
       do: :error

  defp schema_id(module, nil), do: "#{module}:embedded_schema"
  defp schema_id(module, source), do: "#{module}:schema:#{source}"

  defp aliases(expressions) do
    Enum.reduce(expressions, %{}, fn
      {:alias, _meta, args}, aliases ->
        Map.merge(aliases, alias_mappings(args))

      _expression, aliases ->
        aliases
    end)
  end

  defp alias_mappings([target_ast]) do
    with {:ok, target} <- Source.alias_to_string(target_ast) do
      %{alias_name(target) => target}
    else
      :error -> %{}
    end
  end

  defp alias_mappings([target_ast, options]) when is_list(options) do
    with {:ok, target} <- Source.alias_to_string(target_ast),
         {:ok, as} <- alias_option(options, target) do
      %{as => target}
    else
      :error -> %{}
    end
  end

  defp alias_mappings(_args), do: %{}

  defp alias_option(options, target) do
    case Keyword.fetch(options, :as) do
      {:ok, as_ast} -> Source.alias_to_string(as_ast)
      :error -> {:ok, alias_name(target)}
    end
  end

  defp resolve_related(ast, module, association, aliases) do
    with {:ok, related} <- Source.alias_to_string(ast) do
      cond do
        Map.has_key?(aliases, related) ->
          {:ok, Map.fetch!(aliases, related)}

        qualified_alias?(related) ->
          {:ok, related}

        association in [:embeds_one, :embeds_many] ->
          {:ok, "#{module}.#{related}"}

        true ->
          {:ok, qualify_with_parent_module(module, related)}
      end
    end
  end

  defp alias_name(alias) do
    alias
    |> String.split(".")
    |> List.last()
  end

  defp qualified_alias?(alias), do: String.contains?(alias, ".")

  defp qualify_with_parent_module(module, related) do
    case parent_module(module) do
      "" -> related
      parent -> "#{parent}.#{related}"
    end
  end

  defp parent_module(module) do
    module
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.join(".")
  end
end
