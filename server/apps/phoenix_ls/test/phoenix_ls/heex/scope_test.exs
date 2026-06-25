defmodule PhoenixLS.HEEx.ScopeTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.HEEx.Scope
  alias PhoenixLS.Support.Positions

  test "extracts scoped variables from active :for tags" do
    {source, offset} =
      source_and_offset("""
      <div :for={product <- @products}>
        {pro|}
      </div>
      """)

    {:ok, document} = Parser.parse(source)

    assert [
             %Scope.Variable{
               kind: :for,
               name: "product",
               source: {:assign, "products", []}
             }
           ] = Scope.scoped_variables(document.tags, source, offset)
  end

  test "extracts tuple and Enum.with_index variables from active :for tags" do
    {source, offset} =
      source_and_offset("""
      <div :for={{product, index} <- Enum.with_index(@products)}>
        {pro|}{index}
      </div>
      """)

    {:ok, document} = Parser.parse(source)

    bindings = Scope.scoped_variables(document.tags, source, offset)

    assert Enum.map(bindings, & &1.name) == ["product", "index"]

    assert %Scope.Variable{source: {:assign, "products", []}} =
             Enum.find(bindings, &(&1.name == "product"))
  end

  test "extracts scoped variables from slot :let patterns" do
    {source, offset} =
      source_and_offset("""
      <:item :let={{entry, meta}}>
        {en|}
      </:item>
      """)

    {:ok, document} = Parser.parse(source)

    bindings = Scope.scoped_variables(document.tags, source, offset)

    assert Enum.map(bindings, & &1.name) == ["entry", "meta"]
    assert Enum.all?(bindings, &(&1.kind == :let))
  end

  defp source_and_offset(marked_source) do
    [{offset, 1}] = :binary.matches(marked_source, "|")
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, offset)
    {:ok, offset} = Positions.lsp_position_to_offset(source, position)

    {source, offset}
  end
end
