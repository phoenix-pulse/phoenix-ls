defmodule Shop.Catalog.Item do
  use Ecto.Schema

  schema "items" do
    field :name, :string
  end
end
