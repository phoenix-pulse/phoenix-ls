defmodule Phoenix18App.Catalog.Account do
  use Ecto.Schema

  schema "accounts" do
    field :email, :string
    has_many :orders, Phoenix18App.Catalog.Order
  end
end
