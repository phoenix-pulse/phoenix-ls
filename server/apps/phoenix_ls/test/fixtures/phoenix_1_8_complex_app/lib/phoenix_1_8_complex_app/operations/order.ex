defmodule Phoenix18ComplexApp.Operations.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :number, :string
    field :status, :string
    field :total, :decimal
    belongs_to :product, Phoenix18ComplexApp.Catalog.Product
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:number, :status, :total, :product_id])
    |> validate_required([:number, :status])
  end
end
