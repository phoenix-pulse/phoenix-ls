defmodule PhoenixLS.Introspection.ChangesetTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Changeset

  @uri "file:///tmp/app/lib/app/catalog/product.ex"
  @provenance %{source: :test}

  test "extracts exact changeset validation facts" do
    source = """
    defmodule App.Catalog.Product do
      import Ecto.Changeset

      def changeset(product, attrs) do
        product
        |> cast(attrs, [:name, :sku, :price])
        |> validate_required([:name, :sku])
        |> validate_length(:name, min: 2, max: 80)
        |> validate_number(:price, greater_than: 0)
        |> unique_constraint(:sku)
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Changeset.facts_for_module_body("App.Catalog.Product", body, @uri, @provenance)

    assert Enum.map(facts, &{&1.kind, &1.data.validation, &1.data.field}) == [
             {:changeset_validation, :validate_required, "name"},
             {:changeset_validation, :validate_required, "sku"},
             {:changeset_validation, :validate_length, "name"},
             {:changeset_validation, :validate_number, "price"},
             {:changeset_validation, :unique_constraint, "sku"}
           ]

    required =
      Enum.find(facts, &(&1.data.validation == :validate_required and &1.data.field == "name"))

    assert required.id == "App.Catalog.Product:changeset:validate_required:name:6:7"
    assert required.range.start.line == 6

    length = Enum.find(facts, &(&1.data.validation == :validate_length))

    assert length.data == %Changeset.Validation{
             module: "App.Catalog.Product",
             field: "name",
             validation: :validate_length,
             options: [min: 2, max: 80],
             confidence: :exact
           }
  end
end
