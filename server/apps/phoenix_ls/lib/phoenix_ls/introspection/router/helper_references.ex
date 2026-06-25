defmodule PhoenixLS.Introspection.Router.HelperReferences do
  @moduledoc """
  Extracts source-ranged `Routes.*_path` and `Routes.*_url` references.
  """

  alias GenLSP.Structures.{Position, Range}
  alias PhoenixLS.Index.Fact

  defmodule Reference do
    @moduledoc """
    Typed route helper reference payload.
    """

    @enforce_keys [:helper, :helper_base, :variant, :arity]
    defstruct [:helper, :helper_base, :variant, :action, :arity]
  end

  @spec facts(term(), String.t(), keyword()) :: [Fact.t()]
  def facts(quoted, uri, opts \\ []) when is_binary(uri) do
    {_ast, facts} =
      Macro.prewalk(quoted, [], fn
        node, acc ->
          {node, helper_fact(node, uri, opts) ++ acc}
      end)

    Enum.reverse(facts)
  end

  defp helper_fact(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Routes]}, helper]}, call_meta, args},
         uri,
         opts
       )
       when is_atom(helper) and is_list(args) do
    helper = Atom.to_string(helper)

    with {:ok, helper_base, variant} <- helper_parts(helper),
         {:ok, range} <- helper_range(call_meta, helper) do
      [
        Fact.new!(
          kind: :route_helper_reference,
          id: route_helper_reference_id(uri, range),
          uri: uri,
          range: range,
          provenance: provenance(opts),
          data: %Reference{
            helper: helper,
            helper_base: helper_base,
            variant: variant,
            action: helper_action(args),
            arity: length(args)
          }
        )
      ]
    else
      _not_route_helper -> []
    end
  end

  defp helper_fact(_node, _uri, _opts), do: []

  defp helper_action([_conn_or_socket, action | _rest]) when is_atom(action), do: action
  defp helper_action(_args), do: nil

  defp helper_parts(helper) do
    cond do
      String.ends_with?(helper, "_path") ->
        {:ok, String.replace_suffix(helper, "_path", ""), :path}

      String.ends_with?(helper, "_url") ->
        {:ok, String.replace_suffix(helper, "_url", ""), :url}

      true ->
        :error
    end
  end

  defp helper_range(meta, helper) do
    with line when is_integer(line) <- Keyword.get(meta, :line),
         column when is_integer(column) <- Keyword.get(meta, :column) do
      {:ok,
       %Range{
         start: %Position{line: line - 1, character: column - 1},
         end: %Position{line: line - 1, character: column - 1 + byte_size(helper)}
       }}
    else
      _missing_position -> :error
    end
  end

  defp route_helper_reference_id(uri, range) do
    "route-helper:#{uri}:#{range.start.line}:#{range.start.character}"
  end

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
end
