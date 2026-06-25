defmodule PhoenixLS.Features.Diagnostics.HeexStructure do
  @moduledoc """
  High-signal diagnostics for structural HEEx document issues.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.HEEx.Document
  alias PhoenixLS.HEEx.Document.{Attribute, StructuralIssue, Tag}

  @void_elements ~w(area base br col embed hr img input link meta param source track wbr)

  @spec diagnostics(Document.t()) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Document{tags: tags, structure_issues: structure_issues}) do
    issue_diagnostics(structure_issues) ++
      duplicate_attr_diagnostics(tags) ++
      void_element_child_diagnostics(tags)
  end

  defp issue_diagnostics(issues) do
    Enum.map(issues, &issue_diagnostic/1)
  end

  defp issue_diagnostic(%StructuralIssue{
         kind: :mismatched_closing_tag,
         range: range,
         name: actual,
         expected_name: expected
       }) do
    Builder.diagnostic(
      range,
      "phoenix.mismatched_closing_tag",
      "Expected closing tag </#{expected}>, found </#{actual}>.",
      %{
        "kind" => "mismatched_closing_tag",
        "expected" => expected,
        "actual" => actual
      }
    )
  end

  defp issue_diagnostic(%StructuralIssue{
         kind: :unclosed_tag,
         range: range,
         name: name
       }) do
    Builder.diagnostic(
      range,
      "phoenix.unclosed_tag",
      "Tag <#{name}> is missing a closing tag.",
      %{
        "kind" => "unclosed_tag",
        "tag" => name
      }
    )
  end

  defp duplicate_attr_diagnostics(tags) when is_list(tags) do
    Enum.flat_map(tags, &duplicate_attr_diagnostics/1)
  end

  defp duplicate_attr_diagnostics(%Tag{} = tag) do
    {_seen, diagnostics} =
      Enum.reduce(tag.attrs, {MapSet.new(), []}, fn attr, {seen, diagnostics} ->
        cond do
          not literal_attr?(attr) ->
            {seen, diagnostics}

          MapSet.member?(seen, attr.name) ->
            {seen, [duplicate_attr_diagnostic(tag, attr) | diagnostics]}

          true ->
            {MapSet.put(seen, attr.name), diagnostics}
        end
      end)

    Enum.reverse(diagnostics)
  end

  defp duplicate_attr_diagnostic(%Tag{} = tag, %Attribute{} = attr) do
    Builder.diagnostic(
      attr.name_range,
      "phoenix.duplicate_attr",
      ~s(Duplicate attr "#{attr.name}" on #{tag.name}.),
      %{
        "kind" => "duplicate_attr",
        "tag" => tag.name,
        "attr" => attr.name
      }
    )
  end

  defp literal_attr?(%Attribute{name: "{" <> _dynamic}), do: false
  defp literal_attr?(%Attribute{}), do: true

  defp void_element_child_diagnostics(tags) do
    tags
    |> Enum.filter(&void_element_with_child?(&1, tags))
    |> Enum.map(&void_element_child_diagnostic/1)
  end

  defp void_element_with_child?(
         %Tag{kind: :html, name: name, closing_range: closing_range} = tag,
         tags
       )
       when name in @void_elements and not is_nil(closing_range) do
    Enum.any?(tags, &child_tag?(&1, tag))
  end

  defp void_element_with_child?(_tag, _tags), do: false

  defp void_element_child_diagnostic(%Tag{} = tag) do
    Builder.diagnostic(
      tag.name_range,
      "phoenix.void_element_child",
      ~s(Void element "#{tag.name}" must not have child content.),
      %{
        "kind" => "void_element_child",
        "tag" => tag.name
      }
    )
  end

  defp child_tag?(%Tag{} = candidate, %Tag{} = tag) when candidate == tag, do: false

  defp child_tag?(%Tag{} = candidate, %Tag{range: range, closing_range: closing_range}) do
    after_or_equal?(candidate.range.start, range.end) and
      before?(candidate.range.start, closing_range.start)
  end

  defp after_or_equal?(position, other) do
    position.line > other.line or
      (position.line == other.line and position.character >= other.character)
  end

  defp before?(position, other) do
    position.line < other.line or
      (position.line == other.line and position.character < other.character)
  end
end
