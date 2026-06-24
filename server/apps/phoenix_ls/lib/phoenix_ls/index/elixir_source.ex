defmodule PhoenixLS.Index.ElixirSource do
  @moduledoc """
  Extracts source-backed index facts from Elixir source text.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.{Component, LiveView, Router, Schema, Template}

  @parse_options [columns: true, token_metadata: true]

  @spec facts(String.t(), String.t(), keyword()) ::
          {:ok, [Fact.t()]} | {:error, {:parse_error, term()}}
  def facts(uri, source, opts \\ []) when is_binary(uri) and is_binary(source) do
    case Code.string_to_quoted(source, @parse_options) do
      {:ok, quoted} ->
        {:ok,
         collect(quoted, [], uri, opts) ++ Template.render_reference_facts(uri, source, opts)}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp collect({:defmodule, meta, [module_ast, [do: body]]}, module_stack, uri, opts) do
    case module_name(module_ast, module_stack) do
      {:ok, module} ->
        module_fact = module_fact(module, meta, uri, opts)
        provenance = provenance(opts)

        introspection_facts =
          Component.facts_for_module_body(module, body, uri, provenance) ++
            Router.facts_for_module_body(module, body, uri, provenance) ++
            Schema.facts_for_module_body(module, body, uri, provenance) ++
            LiveView.facts_for_module_body(module, body, uri, provenance)

        [module_fact | collect(body, [module | module_stack], uri, opts)] ++ introspection_facts

      :error ->
        collect(body, module_stack, uri, opts)
    end
  end

  defp collect({visibility, meta, [head, _body]}, [module | _rest], uri, opts)
       when visibility in [:def, :defp] do
    case function_signature(head) do
      {:ok, name, arity} ->
        visibility = visibility(visibility)
        range = source_range(meta)
        provenance = provenance(opts)

        [function_fact(module, visibility, name, arity, range, uri, provenance)]

      :error ->
        []
    end
  end

  defp collect({:__block__, _meta, expressions}, module_stack, uri, opts) do
    Enum.flat_map(expressions, &collect(&1, module_stack, uri, opts))
  end

  defp collect(list, module_stack, uri, opts) when is_list(list) do
    Enum.flat_map(list, &collect(&1, module_stack, uri, opts))
  end

  defp collect(tuple, module_stack, uri, opts) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&collect(&1, module_stack, uri, opts))
  end

  defp collect(_node, _module_stack, _uri, _opts), do: []

  defp module_fact(module, meta, uri, opts) do
    Fact.new!(
      kind: :module,
      id: module,
      uri: uri,
      range: source_range(meta),
      provenance: provenance(opts),
      data: %{module: module}
    )
  end

  defp function_fact(module, visibility, name, arity, range, uri, provenance) do
    id = "#{module}.#{name}/#{arity}"

    Fact.new!(
      kind: :function,
      id: id,
      uri: uri,
      range: range,
      provenance: provenance,
      data: %{
        module: module,
        name: name,
        arity: arity,
        visibility: visibility
      }
    )
  end

  defp module_name({:__aliases__, _meta, parts}, []), do: alias_parts(parts)

  defp module_name({:__aliases__, _meta, parts}, [parent | _rest]) do
    case alias_parts(parts) do
      {:ok, module} -> {:ok, "#{parent}.#{module}"}
      :error -> :error
    end
  end

  defp module_name(_ast, _module_stack), do: :error

  defp alias_parts(parts) do
    if Enum.all?(parts, &is_atom/1) do
      {:ok, parts |> Enum.map_join(".", &Atom.to_string/1)}
    else
      :error
    end
  end

  defp function_signature({:when, _meta, [head | _guards]}) do
    function_signature(head)
  end

  defp function_signature({name, _meta, args}) when is_atom(name) and is_list(args) do
    {:ok, Atom.to_string(name), length(args)}
  end

  defp function_signature({name, _meta, nil}) when is_atom(name) do
    {:ok, Atom.to_string(name), 0}
  end

  defp function_signature(_head), do: :error

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

  defp provenance(opts) do
    provenance = %{
      source: :elixir_ast,
      parser: :code_string_to_quoted
    }

    case Keyword.fetch(opts, :version) do
      {:ok, version} -> Map.put(provenance, :document_version, version)
      :error -> provenance
    end
  end

  defp visibility(:def), do: :public
  defp visibility(:defp), do: :private
end
