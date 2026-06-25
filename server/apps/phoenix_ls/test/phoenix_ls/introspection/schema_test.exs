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

    assert schema_fact.data == %Schema.Schema{
             module: "App.Catalog.Product",
             source: "products",
             primary_key: %Schema.PrimaryKey{
               name: "id",
               type: :id,
               options: [autogenerate: true]
             },
             foreign_key_type: :id
           }

    assert [name_field, active_field, account_assoc] = detail_facts

    assert name_field.kind == :schema_field

    assert name_field.data == %Schema.Field{
             schema: schema_fact.id,
             module: "App.Catalog.Product",
             name: "name",
             type: :string,
             options: []
           }

    assert active_field.kind == :schema_field
    assert active_field.data.options == [default: true]

    assert account_assoc.kind == :schema_association

    assert account_assoc.data == %Schema.Association{
             schema: schema_fact.id,
             module: "App.Catalog.Product",
             name: "account",
             association: :belongs_to,
             related: "App.Accounts.Account",
             options: []
           }
  end

  test "extracts embedded schemas and resolves embed association targets" do
    source = """
    defmodule App.Catalog.Product do
      alias App.Inventory.Sku

      schema "products" do
        embeds_one :metadata, Metadata
        embeds_many :variants, Variant
        has_many :skus, Sku
      end

      embedded_schema do
        field :draft_name, :string
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Schema.facts_for_module_body("App.Catalog.Product", body, @uri, @provenance)

    assert Enum.map(facts, & &1.id) == [
             "App.Catalog.Product:schema:products",
             "App.Catalog.Product:schema:products:association:metadata",
             "App.Catalog.Product:schema:products:association:variants",
             "App.Catalog.Product:schema:products:association:skus",
             "App.Catalog.Product:embedded_schema",
             "App.Catalog.Product:embedded_schema:field:draft_name"
           ]

    [metadata_assoc, variants_assoc, skus_assoc] =
      facts
      |> Enum.filter(&(&1.kind == :schema_association))
      |> Enum.map(& &1.data)

    assert metadata_assoc == %Schema.Association{
             schema: "App.Catalog.Product:schema:products",
             module: "App.Catalog.Product",
             name: "metadata",
             association: :embeds_one,
             related: "App.Catalog.Product.Metadata",
             options: []
           }

    assert variants_assoc.related == "App.Catalog.Product.Variant"
    assert variants_assoc.association == :embeds_many
    assert skus_assoc.related == "App.Inventory.Sku"

    assert embedded_schema = Enum.find(facts, &(&1.id == "App.Catalog.Product:embedded_schema"))

    assert embedded_schema.data == %Schema.Schema{
             module: "App.Catalog.Product",
             source: nil,
             primary_key: %Schema.PrimaryKey{
               name: "id",
               type: :id,
               options: [autogenerate: true]
             },
             foreign_key_type: :id
           }

    assert draft_field =
             Enum.find(facts, &(&1.id == "App.Catalog.Product:embedded_schema:field:draft_name"))

    assert draft_field.data.schema == embedded_schema.id
    assert draft_field.data.name == "draft_name"
  end

  test "extracts timestamp fields from timestamps macro" do
    source = """
    defmodule App.Catalog.Product do
      use Ecto.Schema

      schema "products" do
        field :name, :string
        timestamps(type: :utc_datetime)
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Schema.facts_for_module_body("App.Catalog.Product", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :schema_field))
           |> Enum.map(&{&1.data.name, &1.data.type, &1.range.start.line}) == [
             {"name", :string, 4},
             {"inserted_at", :utc_datetime, 5},
             {"updated_at", :utc_datetime, 5}
           ]
  end

  test "extracts primary key and foreign key configuration for schemas" do
    source = """
    defmodule App.Catalog.Product do
      use Ecto.Schema

      @primary_key {:uuid, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      schema "products" do
        belongs_to :account, App.Accounts.Account
      end

      @primary_key false

      embedded_schema do
        field :draft_name, :string
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = Schema.facts_for_module_body("App.Catalog.Product", body, @uri, @provenance)

    assert product_schema = Enum.find(facts, &(&1.id == "App.Catalog.Product:schema:products"))

    assert %{
             name: "uuid",
             type: :binary_id,
             options: [autogenerate: true]
           } = product_schema.data.primary_key

    assert product_schema.data.foreign_key_type == :binary_id

    assert embedded_schema = Enum.find(facts, &(&1.id == "App.Catalog.Product:embedded_schema"))
    assert embedded_schema.data.primary_key == false
    assert embedded_schema.data.foreign_key_type == :binary_id
  end
end
