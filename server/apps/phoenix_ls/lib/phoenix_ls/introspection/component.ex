defmodule PhoenixLS.Introspection.Component do
  @moduledoc """
  Source-only extraction helpers for Phoenix components.
  """

  alias GenLSP.Structures.Range
  alias PhoenixLS.Index.Fact

  @spec function_component_fact(
          String.t(),
          String.t(),
          non_neg_integer(),
          :public | :private,
          term(),
          Range.t(),
          String.t(),
          map()
        ) :: {:ok, Fact.t()} | :none
  def function_component_fact(module, name, 1, :public, body_ast, range, uri, provenance)
      when is_binary(module) and is_binary(name) and is_binary(uri) and is_map(provenance) do
    if contains_heex_sigil?(body_ast) do
      {:ok, component_fact(module, name, range, uri, provenance)}
    else
      :none
    end
  end

  def function_component_fact(
        _module,
        _name,
        _arity,
        _visibility,
        _body_ast,
        _range,
        _uri,
        _provenance
      ),
      do: :none

  defp component_fact(module, name, range, uri, provenance) do
    Fact.new!(
      kind: :component,
      id: "#{module}.#{name}/1",
      uri: uri,
      range: range,
      provenance: provenance,
      data: %{
        module: module,
        name: name,
        arity: 1,
        visibility: :public,
        type: :function
      }
    )
  end

  defp contains_heex_sigil?({:sigil_H, _meta, _args}), do: true

  defp contains_heex_sigil?(list) when is_list(list) do
    Enum.any?(list, &contains_heex_sigil?/1)
  end

  defp contains_heex_sigil?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_heex_sigil?/1)
  end

  defp contains_heex_sigil?(_node), do: false
end
