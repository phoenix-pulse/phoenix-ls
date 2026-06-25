defmodule PhoenixLS.Introspection.LiveView.Navigation do
  @moduledoc """
  Source-only extraction of LiveView navigation reference facts from Elixir AST.
  """

  alias GenLSP.Structures.Range
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source
  alias PhoenixLS.LiveView.Navigation.Reference

  @spec facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    aliases = live_view_aliases(expressions)

    expressions
    |> Enum.flat_map(&navigation_calls(&1, aliases))
    |> Enum.map(fn {navigation, path, range} ->
      Fact.new!(
        kind: :live_navigation_reference,
        id: navigation_id(module, navigation, path, range),
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Reference{
          module: module,
          navigation: navigation,
          path: path
        }
      )
    end)
  end

  defp navigation_calls({:push_patch, meta, [_socket, opts]}, _aliases) do
    navigation_call(:patch, meta, opts)
  end

  defp navigation_calls({:push_patch, meta, [opts]}, _aliases) do
    navigation_call(:patch, meta, opts)
  end

  defp navigation_calls(
         {{:., _dot_meta, [module_ast, :push_patch]}, meta, [_socket, opts]},
         aliases
       ) do
    if live_view_alias?(module_ast, aliases), do: navigation_call(:patch, meta, opts), else: []
  end

  defp navigation_calls(
         {{:., _dot_meta, [module_ast, :push_patch]}, meta, [opts]},
         aliases
       ) do
    if live_view_alias?(module_ast, aliases), do: navigation_call(:patch, meta, opts), else: []
  end

  defp navigation_calls({:push_navigate, meta, [_socket, opts]}, _aliases) do
    navigation_call(:navigate, meta, opts)
  end

  defp navigation_calls({:push_navigate, meta, [opts]}, _aliases) do
    navigation_call(:navigate, meta, opts)
  end

  defp navigation_calls(
         {{:., _dot_meta, [module_ast, :push_navigate]}, meta, [_socket, opts]},
         aliases
       ) do
    if live_view_alias?(module_ast, aliases), do: navigation_call(:navigate, meta, opts), else: []
  end

  defp navigation_calls(
         {{:., _dot_meta, [module_ast, :push_navigate]}, meta, [opts]},
         aliases
       ) do
    if live_view_alias?(module_ast, aliases), do: navigation_call(:navigate, meta, opts), else: []
  end

  defp navigation_calls({:|>, _pipe_meta, [_socket, call]}, aliases) do
    navigation_calls(call, aliases)
  end

  defp navigation_calls(list, aliases) when is_list(list) do
    Enum.flat_map(list, &navigation_calls(&1, aliases))
  end

  defp navigation_calls(tuple, aliases) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&navigation_calls(&1, aliases))
  end

  defp navigation_calls(_node, _aliases), do: []

  defp navigation_call(navigation, call_meta, opts) when is_list(opts) do
    case Keyword.fetch(opts, :to) do
      {:ok, to_ast} ->
        case verified_path(to_ast) do
          {:ok, path} -> [{navigation, path, call_range(call_meta)}]
          :error -> []
        end

      :error ->
        []
    end
  end

  defp navigation_call(_navigation, _call_meta, _opts), do: []

  defp verified_path({:sigil_p, _meta, [{:<<>>, _string_meta, parts}, modifiers]})
       when is_list(parts) and modifiers == [] do
    parts
    |> Enum.reduce_while({:ok, []}, &verified_path_part/2)
    |> case do
      {:ok, path_parts} -> {:ok, Enum.reverse(path_parts) |> Enum.join()}
      :error -> :error
    end
  end

  defp verified_path(_ast), do: :error

  defp verified_path_part(part, {:ok, path_parts}) when is_binary(part) do
    {:cont, {:ok, [part | path_parts]}}
  end

  defp verified_path_part(part, {:ok, path_parts}) do
    if dynamic_interpolation?(part) do
      {:cont, {:ok, [":dynamic" | path_parts]}}
    else
      {:halt, :error}
    end
  end

  defp dynamic_interpolation?(
         {:"::", _meta,
          [
            {{:., _dot_meta, [Kernel, :to_string]}, interpolation_meta, [_value]},
            {:binary, _binary_meta, nil}
          ]}
       ) do
    Keyword.get(interpolation_meta, :from_interpolation) == true
  end

  defp dynamic_interpolation?(_part), do: false

  defp call_range(meta) do
    %Range{
      start: Source.position(meta),
      end: Source.position(Keyword.get(meta, :closing) || meta)
    }
  end

  defp navigation_id(module, navigation, path, %Range{} = range) do
    position = range.start

    "#{module}:live_navigation:#{navigation}:#{path}:#{position.line}:#{position.character}"
  end

  defp live_view_aliases(expressions) do
    expressions
    |> Enum.flat_map(&live_view_alias/1)
    |> MapSet.new()
    |> MapSet.put([:Phoenix, :LiveView])
  end

  defp live_view_alias({:alias, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}]}) do
    [[:LiveView]]
  end

  defp live_view_alias(
         {:alias, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}, opts]}
       )
       when is_list(opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, {:__aliases__, _alias_meta, alias_parts}} when is_list(alias_parts) -> [alias_parts]
      {:ok, alias_name} when is_atom(alias_name) -> [[alias_name]]
      _no_alias -> [[:LiveView]]
    end
  end

  defp live_view_alias(_expression), do: []

  defp live_view_alias?({:__aliases__, _meta, parts}, aliases) do
    MapSet.member?(aliases, parts)
  end

  defp live_view_alias?(_module_ast, _aliases), do: false
end
