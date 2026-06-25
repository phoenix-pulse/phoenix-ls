defmodule PhoenixLS.Features.Definition do
  @moduledoc """
  Go-to-definition locations for Phoenix source facts.
  """

  alias GenLSP.Structures.Location
  alias PhoenixLS.Features.{PhoenixFactLookup, SourceReferenceLookup}
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact

  @spec definition(CursorContext.t(), [Fact.t()]) :: Location.t() | nil
  def definition(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> location()
  end

  @spec definition_source(String.t(), CursorContext.lsp_position(), [Fact.t()]) ::
          Location.t() | nil
  def definition_source(source, position, facts) when is_binary(source) and is_list(facts) do
    source
    |> PhoenixFactLookup.cursor_fact(position, facts)
    |> location()
  end

  @spec definition(String.t(), %{line: non_neg_integer(), character: non_neg_integer()}, [
          Fact.t()
        ]) :: Location.t() | nil
  def definition(uri, position, facts) when is_binary(uri) and is_list(facts) do
    case reference_definition(uri, position, facts) do
      {:ok, definition} -> definition
      :not_found -> nil
    end
  end

  @spec reference_definition(
          String.t(),
          %{line: non_neg_integer(), character: non_neg_integer()},
          [Fact.t()]
        ) :: {:ok, Location.t() | nil} | :not_found
  def reference_definition(uri, position, facts) when is_binary(uri) and is_list(facts) do
    case SourceReferenceLookup.target_result_at(uri, position, facts) do
      {:ok, fact} -> {:ok, location(fact)}
      {:missing_target, _reference} -> {:ok, nil}
      :not_found -> :not_found
    end
  end

  defp location(nil), do: nil

  defp location(%Fact{} = fact) do
    %Location{
      uri: fact.uri,
      range: fact.range
    }
  end
end
