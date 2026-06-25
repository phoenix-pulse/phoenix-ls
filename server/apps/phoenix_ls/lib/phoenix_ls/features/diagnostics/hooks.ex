defmodule PhoenixLS.Features.Diagnostics.Hooks do
  @moduledoc """
  Diagnostics for literal LiveView hook usage in HEEx.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Hooks

  @spec diagnostics(String.t() | nil, [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(uri, facts) when (is_binary(uri) or is_nil(uri)) and is_list(facts) do
    facts
    |> hook_usages(uri)
    |> Enum.reject(&Hooks.known?(&1, facts))
    |> Enum.map(&unknown_hook_diagnostic(&1, facts))
  end

  defp hook_usages(facts, nil), do: Hooks.usages(facts)

  defp hook_usages(facts, uri) do
    facts
    |> Hooks.usages()
    |> Enum.filter(&(&1.uri == uri))
  end

  defp unknown_hook_diagnostic(%Fact{} = usage, facts) do
    name = Hooks.hook_name(usage)

    Builder.diagnostic(
      usage.range,
      "phoenix.unknown_hook",
      ~s(Unknown LiveView hook "#{name}"),
      %{
        "kind" => "unknown_hook",
        "name" => name,
        "attribute" => usage.data.attribute,
        "knownHooks" => Hooks.known_names(facts)
      }
    )
  end
end
