defmodule Phoenix17App.Catalog.Product do
  use Ecto.Schema

  schema "products" do
    field :name, :string
    field :price, :decimal
  end
end
