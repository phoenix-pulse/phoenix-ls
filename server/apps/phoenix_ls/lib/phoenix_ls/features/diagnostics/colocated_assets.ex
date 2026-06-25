defmodule PhoenixLS.Features.Diagnostics.ColocatedAssets do
  @moduledoc """
  Diagnostics for LiveView colocated asset facts.
  """

  alias PhoenixLS.Features.{Diagnostics.Builder, Facts}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks

  @spec diagnostics(String.t() | nil, [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(uri, facts) when (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    facts
    |> colocated_hook_facts(uri)
    |> Enum.reject(&valid_hook_name?/1)
    |> Enum.map(&invalid_hook_name_diagnostic/1)
  end

  defp colocated_hook_facts(facts, nil), do: Facts.by_kind(facts, :colocated_hook)

  defp colocated_hook_facts(facts, uri) do
    facts
    |> Facts.by_kind(:colocated_hook)
    |> Enum.filter(&(&1.uri == uri))
  end

  defp valid_hook_name?(%Fact{data: %{name: name}}) do
    Hooks.valid_colocated_name?(name)
  end

  defp invalid_hook_name_diagnostic(%Fact{} = fact) do
    name = fact.data.name || ""
    expectation = Hooks.colocated_name_expectation()

    Builder.diagnostic(
      fact.data.name_range || fact.range,
      "phoenix.invalid_colocated_hook_name",
      ~s(Invalid colocated hook name "#{name}"),
      %{
        "kind" => "invalid_colocated_hook_name",
        "name" => name,
        "expected" => expectation
      }
    )
  end
end
