defmodule PhoenixLS.Features.AssignAccess do
  @moduledoc """
  Parses assign property access prefixes used by editor features.
  """

  alias PhoenixLS.Features.Completion.SchemaFacts

  @spec field_access(String.t()) :: {:ok, String.t(), [String.t()], String.t()} | :error
  def field_access("@" <> rest), do: split_assign_field(rest)
  def field_access("assigns." <> rest), do: split_assign_field(rest)
  def field_access(_prefix), do: :error

  defp split_assign_field(rest) do
    case String.split(rest, ".") do
      [assign, field_prefix] ->
        validate_parts(assign, [], field_prefix)

      [assign | [_path_segment | _rest] = path_and_field] ->
        {path, [field_prefix]} = Enum.split(path_and_field, -1)
        validate_parts(assign, path, field_prefix)

      _other ->
        :error
    end
  end

  defp validate_parts(assign, path, field_prefix) do
    if SchemaFacts.identifier?(assign) and Enum.all?(path, &SchemaFacts.identifier?/1) do
      {:ok, assign, path, field_prefix || ""}
    else
      :error
    end
  end
end
