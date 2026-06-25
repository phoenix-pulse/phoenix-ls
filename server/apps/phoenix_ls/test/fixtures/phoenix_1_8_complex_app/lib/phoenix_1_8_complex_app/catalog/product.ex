defmodule Phoenix18ComplexApp.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :sku, :string
    field :price, :decimal
    field :active, :boolean, default: true
    has_many :orders, Phoenix18ComplexApp.Operations.Order
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :sku, :price, :active])
    |> validate_required([:name, :sku, :price])
    |> validate_length(:sku, min: 3)
    |> validate_number(:price, greater_than: 0)
    |> unique_constraint(:sku)
  end
end
