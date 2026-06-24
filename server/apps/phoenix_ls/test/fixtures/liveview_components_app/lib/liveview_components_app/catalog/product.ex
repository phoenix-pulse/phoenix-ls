defmodule LiveviewComponentsApp.Catalog.Product do
  use Ecto.Schema

  schema "products" do
    field :name, :string
    field :active, :boolean, default: true
    belongs_to :account, LiveviewComponentsApp.Accounts.Account
  end
end
