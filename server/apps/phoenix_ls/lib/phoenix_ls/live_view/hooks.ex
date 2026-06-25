defmodule PhoenixLS.LiveView.Hooks do
  @moduledoc """
  Shared LiveView hook fact payloads.
  """

  alias PhoenixLS.Index.Fact

  defmodule Hook do
    @moduledoc """
    Typed LiveView JavaScript hook definition fact payload.
    """

    @enforce_keys [:name, :source]
    defstruct [:name, :source]
  end

  defmodule HookUsage do
    @moduledoc """
    Typed HEEx LiveView hook usage fact payload.
    """

    @enforce_keys [:module, :name, :attribute, :tag]
    defstruct [:module, :name, :attribute, :tag]
  end

  @spec definitions([Fact.t()]) :: [Fact.t()]
  def definitions(facts) when is_list(facts) do
    facts
    |> Enum.filter(&match?(%Fact{kind: :hook}, &1))
    |> Enum.sort_by(&{hook_name(&1), &1.uri})
  end

  @spec usages([Fact.t()]) :: [Fact.t()]
  def usages(facts) when is_list(facts) do
    facts
    |> Enum.filter(&match?(%Fact{kind: :hook_usage}, &1))
    |> Enum.sort_by(&{hook_name(&1), &1.uri, &1.range.start.line, &1.range.start.character})
  end

  @spec known_names([Fact.t()]) :: [String.t()]
  def known_names(facts) when is_list(facts) do
    facts
    |> definitions()
    |> Enum.map(&hook_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec known?(String.t() | Fact.t(), [Fact.t()]) :: boolean()
  def known?(name_or_usage, facts) when is_list(facts) do
    name = hook_name(name_or_usage)

    is_binary(name) and name in known_names(facts)
  end

  @spec valid_colocated_name?(term()) :: boolean()
  def valid_colocated_name?("." <> local_name), do: pascal_identifier?(local_name)
  def valid_colocated_name?(_name), do: false

  @spec colocated_name_expectation() :: String.t()
  def colocated_name_expectation, do: "dot-prefixed PascalCase, for example .Sortable"

  @spec definition_for_usage(Fact.t(), [Fact.t()]) :: Fact.t() | nil
  def definition_for_usage(%Fact{kind: :hook_usage} = usage, facts) when is_list(facts) do
    Enum.find(definitions(facts), &same_name?(&1, usage))
  end

  def definition_for_usage(_usage, _facts), do: nil

  @spec hook_name(String.t() | Fact.t()) :: String.t() | nil
  def hook_name(name) when is_binary(name), do: name
  def hook_name(%Fact{kind: :hook, data: %Hook{name: name}}), do: name
  def hook_name(%Fact{kind: :hook_usage, data: %HookUsage{name: name}}), do: name
  def hook_name(_value), do: nil

  defp same_name?(definition, usage) do
    hook_name(definition) == hook_name(usage)
  end

  defp pascal_identifier?(""), do: false

  defp pascal_identifier?(name) do
    case String.graphemes(name) do
      [first | rest] -> uppercase_ascii?(first) and Enum.all?(rest, &identifier_part?/1)
      [] -> false
    end
  end

  defp uppercase_ascii?(<<char>>) when char in ?A..?Z, do: true
  defp uppercase_ascii?(_grapheme), do: false

  defp identifier_part?(<<char>>) when char in ?A..?Z, do: true
  defp identifier_part?(<<char>>) when char in ?a..?z, do: true
  defp identifier_part?(<<char>>) when char in ?0..?9, do: true
  defp identifier_part?("_"), do: true
  defp identifier_part?(_grapheme), do: false
end
