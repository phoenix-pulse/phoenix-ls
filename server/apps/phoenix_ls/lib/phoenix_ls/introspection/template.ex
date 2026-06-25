defmodule PhoenixLS.Introspection.Template do
  @moduledoc """
  Source-only extraction helpers for HEEx template documents and references.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.HEEx.Document.Attribute
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions
  alias PhoenixLS.Support.URI, as: SupportURI
  alias PhoenixLS.Introspection.Template.ColocatedAssets
  alias PhoenixLS.Introspection.Template.RenderReferences
  alias PhoenixLS.Introspection.Template.Hooks, as: TemplateHooks
  alias PhoenixLS.Introspection.Template.Uploads
  alias PhoenixLS.Introspection.Source
  alias PhoenixLS.LiveView.Attributes

  @parse_options [columns: true, token_metadata: true]

  defmodule Template do
    @moduledoc """
    Typed HEEx template fact payload.
    """

    @enforce_keys [:format, :name, :module, :kind]
    defstruct [:format, :name, :module, :kind]
  end

  defmodule EventUsage do
    @moduledoc """
    Typed HEEx LiveView event usage fact payload.
    """

    @enforce_keys [:module, :event, :attribute, :handler, :arity]
    defstruct [:module, :event, :attribute, :handler, :arity]
  end

  @spec facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)
    provenance = provenance(opts)

    [template_fact(uri, source, metadata, provenance)]
  end

  @spec index_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def index_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)
    provenance = provenance(opts)
    template_facts = [template_fact(uri, source, metadata, provenance)]

    case Parser.parse(source) do
      {:ok, document} ->
        template_facts ++
          event_usage_facts(document, uri, metadata.module, provenance) ++
          Uploads.facts(uri, document, metadata, provenance) ++
          TemplateHooks.facts(uri, document, metadata, provenance) ++
          ColocatedAssets.facts(uri, document, metadata, provenance)

      {:error, _reason} ->
        template_facts
    end
  end

  @spec event_usage_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def event_usage_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)

    case Parser.parse(source) do
      {:ok, document} ->
        event_usage_facts(document, uri, metadata.module, provenance(opts))

      {:error, _reason} ->
        []
    end
  end

  @spec render_reference_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def render_reference_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    RenderReferences.facts(uri, source, opts)
  end

  @spec upload_usage_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def upload_usage_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)

    case Parser.parse(source) do
      {:ok, document} ->
        Uploads.facts(uri, document, metadata, provenance(opts))

      {:error, _reason} ->
        []
    end
  end

  @spec hook_usage_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def hook_usage_facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)

    case Parser.parse(source) do
      {:ok, document} ->
        TemplateHooks.facts(uri, document, metadata, provenance(opts))

      {:error, _reason} ->
        []
    end
  end

  @spec colocated_asset_facts(String.t(), String.t(), keyword()) :: [Fact.t()]
  def colocated_asset_facts(uri, source, opts \\ [])
      when is_binary(uri) and is_binary(source) do
    metadata = template_metadata(uri)

    case Parser.parse(source) do
      {:ok, document} ->
        ColocatedAssets.facts(uri, document, metadata, provenance(opts))

      {:error, _reason} ->
        []
    end
  end

  defp document_range(source) do
    {:ok, end_position} = Positions.offset_to_lsp_position(source, byte_size(source))

    %Range{
      start: %Position{line: 0, character: 0},
      end: position(end_position)
    }
  end

  defp position(%{line: line, character: character}) do
    %Position{line: line, character: character}
  end

  defp template_fact(uri, source, metadata, provenance) do
    Fact.new!(
      kind: :template,
      id: uri,
      uri: uri,
      range: document_range(source),
      provenance: provenance,
      data: %Template{
        format: :heex,
        name: metadata.name,
        module: metadata.module,
        kind: metadata.kind
      }
    )
  end

  defp event_usage_facts(document, uri, module, provenance) do
    document.tags
    |> Enum.flat_map(& &1.attrs)
    |> Enum.filter(&event_attr?/1)
    |> Enum.filter(&literal_attr_value?/1)
    |> Enum.reject(&blank?(&1.value))
    |> Enum.map(&event_usage_fact(&1, uri, module, provenance))
  end

  defp provenance(opts) do
    provenance = %{
      source: :heex_template
    }

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end

  defp template_metadata(uri) do
    path = file_path(uri)

    embedded_template_metadata(path) || path_template_metadata(path)
  end

  defp path_template_metadata(path) do
    name = template_name(path)
    {module_parts, kind} = module_parts(path, name)

    %{
      name: name,
      module: Enum.join(module_parts, "."),
      kind: kind
    }
  end

  defp event_usage_fact(%Attribute{} = attr, uri, module, provenance) do
    Fact.new!(
      kind: :live_event_usage,
      id: event_usage_id(uri, attr),
      uri: uri,
      range: attr.value_range || attr.name_range,
      provenance: provenance,
      data: %EventUsage{
        module: module,
        event: attr.value,
        attribute: attr.name,
        handler: "handle_event/3",
        arity: 3
      }
    )
  end

  defp event_usage_id(uri, %Attribute{} = attr) do
    position = (attr.value_range || attr.name_range).start

    "#{uri}:event_usage:#{attr.name}:#{attr.value}:#{position.line}:#{position.character}"
  end

  defp event_attr?(%Attribute{name: name}), do: Attributes.event_attr?(name)

  defp literal_attr_value?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_attr_value?(_attr), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp file_path(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, _reason} -> uri
    end
  end

  defp template_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp module_parts(path, name) do
    case Enum.split_while(Path.split(path), &(&1 != "lib")) do
      {_before_lib, ["lib", web_root | rest]} ->
        {suffix, kind} =
          rest
          |> Enum.drop(-1)
          |> module_suffix(template_stem(name))

        {[module_segment(web_root) | suffix] |> Enum.reject(&(&1 == "")), kind}

      _path_without_lib ->
        {[], :template}
    end
  end

  defp module_suffix(["controllers"], stem) do
    {[module_segment(stem)], :controller}
  end

  defp module_suffix(["controllers" | dirs], _stem) do
    {Enum.map(dirs, &module_segment/1), :controller}
  end

  defp module_suffix(["components", "layouts" | dirs], _stem) do
    {Enum.map(["layouts" | dirs], &module_segment/1), :layout}
  end

  defp module_suffix(["components"], stem) do
    kind = if stem in ["layout", "layouts"], do: :layout, else: :component

    {[module_segment(stem)], kind}
  end

  defp module_suffix(["components" | dirs], _stem) do
    {Enum.map(dirs, &module_segment/1), :component}
  end

  defp module_suffix(["live" | dirs], stem) do
    {Enum.map(dirs ++ [stem], &module_segment/1), :live_view}
  end

  defp module_suffix(["templates", layout_dir | _dirs], _stem)
       when layout_dir in ["layout", "layouts"] do
    {["LayoutView"], :layout}
  end

  defp module_suffix(["templates" | dirs], _stem) do
    {legacy_template_module_parts(dirs), :controller}
  end

  defp module_suffix(dirs, _stem) do
    {
      dirs
      |> Enum.reject(&template_context_dir?/1)
      |> Enum.map(&module_segment/1),
      :template
    }
  end

  defp template_context_dir?(dir), do: dir in ["controllers", "live", "templates", "components"]

  defp legacy_template_module_parts([]), do: []

  defp legacy_template_module_parts(dirs) do
    {parents, [view_dir]} = Enum.split(dirs, -1)

    Enum.map(parents, &module_segment/1) ++ [module_segment(view_dir) <> "View"]
  end

  defp embedded_template_metadata(path) do
    path
    |> candidate_module_files()
    |> Enum.find_value(&embedded_template_metadata(&1, path))
  end

  defp embedded_template_metadata(module_path, template_path) do
    with true <- File.regular?(module_path),
         {:ok, source} <- File.read(module_path),
         {:ok, quoted} <- Code.string_to_quoted(source, @parse_options),
         {:ok, module} <- embedded_template_owner(quoted, module_path, template_path) do
      %{
        name: template_name(template_path),
        module: module,
        kind: owner_template_kind(module_path, module)
      }
    else
      _ignored -> nil
    end
  end

  defp candidate_module_files(path) do
    template_dir = Path.dirname(path)
    parent_dir = Path.dirname(template_dir)
    stem = template_stem(template_name(path))

    [
      Path.join(template_dir, stem <> ".ex"),
      Path.join(parent_dir, Path.basename(template_dir) <> ".ex")
    ]
    |> Kernel.++(Path.wildcard(Path.join(parent_dir, "*.ex")))
    |> Enum.uniq()
  end

  defp embedded_template_owner(quoted, module_path, template_path) do
    {_quoted, owners} =
      Macro.prewalk(quoted, [], fn
        {:defmodule, _meta, [module_ast, [do: body]]} = node, acc ->
          owner =
            with {:ok, module} <- Source.alias_to_string(module_ast),
                 true <- module_embeds_template?(body, module_path, template_path) do
              module
            else
              _ignored -> nil
            end

          {node, maybe_cons(owner, acc)}

        node, acc ->
          {node, acc}
      end)

    case Enum.reverse(owners) do
      [module | _rest] -> {:ok, module}
      [] -> :error
    end
  end

  defp module_embeds_template?(body, module_path, template_path) do
    body
    |> embed_template_patterns()
    |> Enum.any?(&embed_pattern_matches?(&1, module_path, template_path))
  end

  defp embed_template_patterns(body) do
    {_body, patterns} =
      Macro.prewalk(body, [], fn
        {:embed_templates, _meta, [pattern | _rest]} = node, acc when is_binary(pattern) ->
          {node, [pattern | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patterns)
  end

  defp embed_pattern_matches?(pattern, module_path, template_path) do
    module_path
    |> Path.dirname()
    |> Path.join(pattern)
    |> Path.expand()
    |> Path.wildcard()
    |> Enum.any?(&(Path.expand(&1) == Path.expand(template_path)))
  end

  defp maybe_cons(nil, acc), do: acc
  defp maybe_cons(value, acc), do: [value | acc]

  defp owner_template_kind(module_path, module) do
    path_parts = Path.split(module_path)
    basename = module_path |> Path.basename() |> Path.rootname()

    cond do
      "controllers" in path_parts ->
        :controller

      "views" in path_parts and basename in ["layout_view", "layouts_view"] ->
        :layout

      "views" in path_parts ->
        :controller

      "components" in path_parts and String.ends_with?(module, ".Layouts") ->
        :layout

      "components" in path_parts ->
        :component

      "live" in path_parts ->
        :live_view

      true ->
        :template
    end
  end

  defp template_stem(name) do
    name
    |> String.split(".", parts: 2)
    |> List.first()
  end

  defp module_segment(segment) do
    segment
    |> String.split("_")
    |> Enum.map(&module_word/1)
    |> Enum.join()
  end

  defp module_word(""), do: ""
  defp module_word("api"), do: "API"
  defp module_word("html"), do: "HTML"
  defp module_word("json"), do: "JSON"
  defp module_word(word), do: String.capitalize(word)
end
