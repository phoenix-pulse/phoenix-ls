defmodule PhoenixLS.Introspection.SchemaTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Schema

  @uri "file:///tmp/app/lib/app/catalog/product.ex"
  @provenance %{source: :test}

  test "extracts Ecto schema fields and associations with source ranges" do
    source = """
    defmodule App.Catalog.Product do
      use Ecto.Schema

      schema "products" do
        field :name, :string
        field :active, :boolean, default: true
        belongs_to :account, App.Accounts.Account
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Schema.facts_for_module_body("App.Catalog.Product", body, @uri, @provenance)

    assert Enum.map(facts, & &1.id) == [
             "App.Catalog.Product:schema:products",
             "App.Catalog.Product:schema:products:field:name",
             "App.Catalog.Product:schema:products:field:active",
             "App.Catalog.Product:schema:products:association:account"
           ]

    assert [schema_fact | detail_facts] = facts

    assert schema_fact.kind == :schema
    assert schema_fact.range.start.line == 3

    assert schema_fact.data == %{
             module: "App.Catalog.Product",
             source: "products"
           }

    assert [name_field, active_field, account_assoc] = detail_facts

    assert name_field.kind == :schema_field

    assert name_field.data == %{
             schema: schema_fact.id,
             module: "App.Catalog.Product",
             name: "name",
             type: :string,
             options: []
           }

    assert active_field.kind == :schema_field
    assert active_field.data.options == [default: true]

    assert account_assoc.kind == :schema_association

    assert account_assoc.data == %{
             schema: schema_fact.id,
             module: "App.Catalog.Product",
             name: "account",
             association: :belongs_to,
             related: "App.Accounts.Account",
             options: []
           }
  end
end
