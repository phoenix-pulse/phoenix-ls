defmodule PhoenixLS.Introspection.Template.ColocatedAssets do
  @moduledoc """
  Extracts source-ranged LiveView colocated asset facts from parsed HEEx documents.
  """

  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source

  @parse_options [columns: true, token_metadata: true]

  @types [
    %{
      kind: :colocated_hook,
      type_module: "Phoenix.LiveView.ColocatedHook",
      tag: "script",
      generated_suffix: nil
    },
    %{
      kind: :colocated_js,
      type_module: "Phoenix.LiveView.ColocatedJS",
      tag: "script",
      generated_suffix: "ColocatedJS"
    },
    %{
      kind: :colocated_css,
      type_module: "Phoenix.LiveView.ColocatedCSS",
      tag: "style",
      generated_suffix: "ColocatedCSS"
    }
  ]

  defmodule Asset do
    @moduledoc """
    Typed HEEx colocated asset fact payload.
    """

    @enforce_keys [:owner_module, :type_module, :source_range, :tag, :options]
    defstruct [
      :owner_module,
      :type_module,
      :source_range,
      :name,
      :name_range,
      :generated_name,
      :tag,
      :options
    ]
  end

  @spec type_definitions() :: [map()]
  def type_definitions, do: @types

  @spec type_modules() :: [String.t()]
  def type_modules, do: Enum.map(@types, & &1.type_module)

  @spec kind_for_type(String.t()) :: atom() | nil
  def kind_for_type(type_module) when is_binary(type_module) do
    case type_definition(type_module) do
      nil -> nil
      definition -> definition.kind
    end
  end

  @spec facts(String.t(), Document.t(), map(), map()) :: [Fact.t()]
  def facts(uri, %Document{} = document, metadata, provenance)
      when is_binary(uri) and is_map(metadata) and is_map(provenance) do
    owner_module = Map.get(metadata, :module, "")

    document.tags
    |> Enum.flat_map(&tag_facts(&1, uri, owner_module, provenance))
    |> Enum.sort_by(&fact_position/1)
  end

  defp tag_facts(%Tag{} = tag, uri, owner_module, provenance) do
    with %Attribute{} = type_attr <- attr(tag, ":type"),
         {:ok, type_module} <- type_module(type_attr),
         %{tag: expected_tag} = definition <- type_definition(type_module),
         true <- tag.name == expected_tag do
      [asset_fact(tag, uri, owner_module, provenance, definition, type_module)]
    else
      _not_colocated_asset -> []
    end
  end

  defp asset_fact(%Tag{} = tag, uri, owner_module, provenance, definition, type_module) do
    {name, name_range} = literal_option(tag, "name")
    options = options(tag)

    Fact.new!(
      kind: definition.kind,
      id: asset_id(uri, definition.kind, type_module, tag.range),
      uri: uri,
      range: tag.range,
      provenance: provenance,
      data: %Asset{
        owner_module: owner_module,
        type_module: type_module,
        source_range: tag.range,
        name: name,
        name_range: name_range,
        generated_name: generated_name(owner_module, name, definition.generated_suffix),
        tag: tag.name,
        options: options
      }
    )
  end

  defp type_module(%Attribute{value_kind: :expression, value: value}) when is_binary(value) do
    with {:ok, ast} <- Code.string_to_quoted(value, @parse_options),
         {:ok, module} <- Source.alias_to_string(ast),
         %{} <- type_definition(module) do
      {:ok, module}
    else
      _invalid_or_unknown -> :error
    end
  end

  defp type_module(_attr), do: :error

  defp type_definition(type_module) when is_binary(type_module) do
    Enum.find(@types, fn definition ->
      definition.type_module == type_module or
        String.ends_with?(
          type_module,
          "." <> List.last(String.split(definition.type_module, "."))
        )
    end)
  end

  defp options(%Tag{attrs: attrs}) do
    attrs
    |> Enum.reject(&(&1.name == ":type"))
    |> Enum.filter(&literal_attr_value?/1)
    |> Map.new(&{&1.name, &1.value})
  end

  defp literal_option(%Tag{} = tag, name) do
    case attr(tag, name) do
      %Attribute{value_kind: kind, value: value, value_range: range}
      when kind in [:quoted, :unquoted] ->
        {value, range}

      _missing_or_dynamic ->
        {nil, nil}
    end
  end

  defp attr(%Tag{attrs: attrs}, name), do: Enum.find(attrs, &(&1.name == name))

  defp literal_attr_value?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_attr_value?(_attr), do: false

  defp generated_name("", _name, _suffix), do: nil
  defp generated_name(nil, _name, _suffix), do: nil

  defp generated_name(owner_module, "." <> local_name, nil) do
    owner_module <> "." <> local_name
  end

  defp generated_name(owner_module, _name, suffix) when is_binary(suffix) do
    owner_module <> "." <> suffix
  end

  defp generated_name(_owner_module, _name, _suffix), do: nil

  defp asset_id(uri, kind, type_module, range) do
    position = range.start

    "#{uri}:#{kind}:#{type_module}:#{position.line}:#{position.character}"
  end

  defp fact_position(%Fact{range: range, data: data}) do
    {range.start.line, range.start.character, data.type_module}
  end
end
