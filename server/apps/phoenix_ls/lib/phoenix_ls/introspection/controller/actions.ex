defmodule PhoenixLS.Introspection.Controller.Actions do
  @moduledoc """
  Extracts source-ranged Phoenix controller action facts.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Controller.Action
  alias PhoenixLS.Introspection.Source

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:name, :arity, :range, :body]
    defstruct [:name, :arity, :range, :body]
  end

  @spec entries([term()]) :: [Entry.t()]
  def entries(expressions) when is_list(expressions) do
    expressions
    |> Enum.flat_map(fn
      {:def, meta, [head, body_ast]} ->
        case action_signature(head) do
          {:ok, name, arity} ->
            [
              %Entry{
                name: name,
                arity: arity,
                range: Source.source_range(meta),
                body: body(body_ast)
              }
            ]

          :error ->
            []
        end

      _expression ->
        []
    end)
  end

  @spec facts(String.t(), [Entry.t()], String.t(), map()) :: [Fact.t()]
  def facts(module, entries, uri, provenance)
      when is_binary(module) and is_list(entries) and is_binary(uri) and is_map(provenance) do
    Enum.map(entries, fn %Entry{} = entry ->
      Fact.new!(
        kind: :controller_action,
        id: "#{module}:action:#{entry.name}",
        uri: uri,
        range: entry.range,
        provenance: provenance,
        data: %Action{
          module: module,
          action: entry.name,
          arity: entry.arity
        }
      )
    end)
  end

  defp action_signature({:when, _meta, [head | _guards]}), do: action_signature(head)

  defp action_signature({name, _meta, args}) when is_atom(name) and is_list(args) do
    arity = length(args)

    if arity == 2 do
      {:ok, Atom.to_string(name), arity}
    else
      :error
    end
  end

  defp action_signature(_head), do: :error

  defp body(do: body), do: body
  defp body(keyword) when is_list(keyword), do: Keyword.get(keyword, :do)
  defp body(body), do: body
end
