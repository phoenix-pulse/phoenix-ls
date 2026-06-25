defmodule PhoenixLS.Features.Completion.ScopedVariables do
  @moduledoc """
  Completion items for HEEx variables introduced by active `:for` and `:let` scopes.
  """

  alias GenLSP.Enumerations.{CompletionItemKind, InsertTextFormat}
  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.HEEx.Scope.Variable
  alias PhoenixLS.Support.Positions

  @spec complete(String.t(), Positions.lsp_position(), CursorContext.t()) :: [CompletionItem.t()]
  def complete(source, position, %CursorContext{kind: :expression, prefix: prefix})
      when is_binary(source) do
    with true <- variable_prefix?(prefix || ""),
         {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, document} <- Parser.parse(source) do
      document.tags
      |> Scope.scoped_variables(source, offset)
      |> Enum.filter(&String.starts_with?(&1.name, prefix || ""))
      |> Enum.map(&item/1)
    else
      _not_variable_context -> []
    end
  end

  def complete(_source, _position, %CursorContext{}), do: []

  defp item(%Variable{} = variable) do
    %CompletionItem{
      label: variable.name,
      kind: CompletionItemKind.variable(),
      detail: "HEEx #{variable_attr(variable.kind)} binding",
      insert_text: variable.name,
      insert_text_format: InsertTextFormat.plain_text(),
      data: %{"kind" => "heex_scoped_variable", "name" => variable.name}
    }
  end

  defp variable_attr(:for), do: ":for"
  defp variable_attr(:let), do: ":let"

  defp variable_prefix?(""), do: false
  defp variable_prefix?("@" <> _rest), do: false
  defp variable_prefix?("~p\"" <> _rest), do: false
  defp variable_prefix?("~p'" <> _rest), do: false
  defp variable_prefix?("JS." <> _rest), do: false
  defp variable_prefix?("Routes." <> _rest), do: false

  defp variable_prefix?(<<first::utf8, rest::binary>>) do
    identifier_start?(first) and rest_identifier?(rest)
  end

  defp variable_prefix?(_prefix), do: false

  defp rest_identifier?(<<char::utf8, rest::binary>>) do
    identifier_char?(char) and rest_identifier?(rest)
  end

  defp rest_identifier?(""), do: true

  defp identifier_start?(char), do: char == ?_ or lower?(char) or upper?(char)
  defp identifier_char?(char), do: identifier_start?(char) or digit?(char)

  defp lower?(char), do: char >= ?a and char <= ?z
  defp upper?(char), do: char >= ?A and char <= ?Z
  defp digit?(char), do: char >= ?0 and char <= ?9
end
