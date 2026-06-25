defmodule PhoenixLS.Introspection.Template.Uploads do
  @moduledoc """
  Extracts source-ranged LiveView upload usage facts from parsed HEEx documents.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, Expression, Tag}
  alias PhoenixLS.Index.Fact

  @parse_options [columns: true, token_metadata: true]

  defmodule UploadUsage do
    @moduledoc """
    Typed HEEx upload usage fact payload.
    """

    @enforce_keys [:module, :upload, :role]
    defstruct [:module, :upload, :role, :attribute, :function, :tag]
  end

  @spec facts(String.t(), Document.t(), map(), map()) :: [Fact.t()]
  def facts(uri, %Document{} = document, metadata, provenance)
      when is_binary(uri) and is_map(metadata) and is_map(provenance) do
    module = Map.get(metadata, :module, "")

    (expression_facts(document.expressions, uri, module, provenance) ++
       tag_facts(document.tags, uri, module, provenance))
    |> Enum.sort_by(&fact_position/1)
  end

  defp expression_facts(expressions, uri, module, provenance) do
    Enum.flat_map(expressions, &expression_fact(&1, uri, module, provenance))
  end

  defp expression_fact(%Expression{value: value, value_range: range}, uri, module, provenance) do
    with {:ok, ast} <- parse_expression(value) do
      ast
      |> expression_usages(range)
      |> Enum.map(fn usage ->
        upload_usage_fact(
          uri,
          Map.get(usage, :range, range),
          provenance,
          module,
          usage.upload,
          usage.role,
          function: usage[:function]
        )
      end)
    else
      _dynamic_or_unrelated -> []
    end
  end

  defp tag_facts(tags, uri, module, provenance) do
    Enum.flat_map(tags, &tag_fact(&1, uri, module, provenance))
  end

  defp tag_fact(%Tag{name: ".live_file_input", attrs: attrs} = tag, uri, module, provenance) do
    attrs
    |> Enum.find(&(&1.name == "upload"))
    |> live_file_input_fact(tag, uri, module, provenance)
  end

  defp tag_fact(%Tag{attrs: attrs}, uri, module, provenance) do
    attrs
    |> Enum.find(&(&1.name == "phx-drop-target"))
    |> drop_target_fact(uri, module, provenance)
  end

  defp live_file_input_fact(
         %Attribute{value: value, value_kind: :expression, value_range: range},
         %Tag{name: tag_name},
         uri,
         module,
         provenance
       ) do
    with {:ok, ast} <- parse_expression(value),
         {:ok, upload} <- upload_name(ast) do
      [
        upload_usage_fact(uri, range, provenance, module, upload, :live_file_input,
          attribute: "upload",
          tag: tag_name
        )
      ]
    else
      _dynamic_or_unrelated -> []
    end
  end

  defp live_file_input_fact(_attr, _tag, _uri, _module, _provenance), do: []

  defp drop_target_fact(
         %Attribute{value: value, value_kind: :expression, value_range: range} = attr,
         uri,
         module,
         provenance
       ) do
    with {:ok, ast} <- parse_expression(value),
         {:ok, upload} <- upload_ref_name(ast) do
      [
        upload_usage_fact(uri, range, provenance, module, upload, :drop_target,
          attribute: attr.name
        )
      ]
    else
      _dynamic_or_unrelated -> []
    end
  end

  defp drop_target_fact(_attr, _uri, _module, _provenance), do: []

  defp expression_usages(ast, range) do
    case upload_errors_usage(ast) do
      {:ok, usage} -> [usage]
      :error -> upload_assign_usages(ast, range)
    end
  end

  defp upload_assign_usages(ast, base_range) do
    {_ast, uploads} =
      Macro.prewalk(ast, MapSet.new(), fn node, uploads ->
        case upload_prefix(node, base_range) do
          {:ok, upload, range} -> {node, MapSet.put(uploads, {upload, range})}
          :error -> {node, uploads}
        end
      end)

    uploads
    |> MapSet.to_list()
    |> Enum.sort_by(fn {upload, range} -> {upload, range.start.line, range.start.character} end)
    |> Enum.map(fn {upload, range} -> %{upload: upload, role: :assign, range: range} end)
  end

  defp upload_errors_usage({:upload_errors, _meta, args}) when is_list(args) do
    case args do
      [upload_ast] -> upload_errors_usage(upload_ast, 1)
      [upload_ast, _kind_ast] -> upload_errors_usage(upload_ast, 2)
      _other_arity -> :error
    end
  end

  defp upload_errors_usage(_ast), do: :error

  defp upload_errors_usage(upload_ast, arity) do
    with {:ok, upload} <- upload_name(upload_ast) do
      {:ok, %{upload: upload, role: :upload_errors, function: "upload_errors/#{arity}"}}
    end
  end

  defp upload_name(ast) do
    case upload_path(ast) do
      {:ok, [upload]} -> {:ok, upload}
      _dynamic_or_unrelated -> :error
    end
  end

  defp upload_prefix(ast, base_range) do
    case upload_path_info(ast, base_range) do
      {:ok, [upload | _path], %Range{} = range} -> {:ok, upload, range}
      _dynamic_or_unrelated -> :error
    end
  end

  defp upload_ref_name(ast) do
    case upload_path(ast) do
      {:ok, [upload, "ref"]} -> {:ok, upload}
      _dynamic_or_unrelated -> :error
    end
  end

  defp upload_path({{:., _dot_meta, [left_ast, member]}, _call_meta, []}) when is_atom(member) do
    with {:ok, path} <- upload_path(left_ast) do
      {:ok, path ++ [Atom.to_string(member)]}
    end
  end

  defp upload_path({:@, _meta, [{:uploads, _uploads_meta, nil}]}), do: {:ok, []}
  defp upload_path(_ast), do: :error

  defp upload_path_info({{:., _dot_meta, [left_ast, member]}, call_meta, []}, base_range)
       when is_atom(member) do
    with {:ok, path, prefix_range} <- upload_path_info(left_ast, base_range) do
      member_name = Atom.to_string(member)

      case path do
        [] ->
          {:ok, [member_name], upload_prefix_range(left_ast, call_meta, member_name, base_range)}

        _path ->
          {:ok, path ++ [member_name], prefix_range}
      end
    end
  end

  defp upload_path_info({:@, _meta, [{:uploads, _uploads_meta, nil}]}, _base_range),
    do: {:ok, [], nil}

  defp upload_path_info(_ast, _base_range), do: :error

  defp upload_prefix_range(
         {:@, start_meta, [{:uploads, _uploads_meta, nil}]},
         end_meta,
         upload,
         base_range
       ) do
    start = absolute_position(base_range, start_meta)
    upload_start = absolute_position(base_range, end_meta)
    finish = %Position{upload_start | character: upload_start.character + String.length(upload)}

    %Range{start: start, end: finish}
  end

  defp parse_expression(value) when is_binary(value) do
    case Code.string_to_quoted(value, @parse_options) do
      {:ok, ast} -> {:ok, ast}
      {:error, _reason} -> Code.string_to_quoted(value <> "\n nil\nend", @parse_options)
    end
  end

  defp upload_usage_fact(uri, range, provenance, module, upload, role, opts) do
    Fact.new!(
      kind: :upload_usage,
      id: upload_usage_id(uri, role, upload, range),
      uri: uri,
      range: range,
      provenance: provenance,
      data: %UploadUsage{
        module: module,
        upload: upload,
        role: role,
        attribute: Keyword.get(opts, :attribute),
        function: Keyword.get(opts, :function),
        tag: Keyword.get(opts, :tag)
      }
    )
  end

  defp upload_usage_id(uri, role, upload, range) do
    position = range.start

    "#{uri}:upload_usage:#{role}:#{upload}:#{position.line}:#{position.character}"
  end

  defp fact_position(%Fact{range: range, data: data}) do
    {range.start.line, range.start.character, data.role}
  end

  defp absolute_position(%Range{start: base}, meta) do
    line_offset = meta |> Keyword.get(:line, 1) |> zero_based()
    character = meta |> Keyword.get(:column, 1) |> zero_based()

    %Position{
      line: base.line + line_offset,
      character: if(line_offset == 0, do: base.character + character, else: character)
    }
  end

  defp zero_based(value) when is_integer(value) and value > 0, do: value - 1
  defp zero_based(_value), do: 0
end
