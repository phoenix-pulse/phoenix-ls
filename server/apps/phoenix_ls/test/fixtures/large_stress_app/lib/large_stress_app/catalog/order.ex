defmodule LargeStressApp.Catalog.Order do
  use Ecto.Schema

  schema "orders" do
    field(:number, :string)
    field(:status, :string)
    field(:total_cents, :integer)
    field(:currency, :string)
    field(:placed_at, :utc_datetime)
    field(:customer_email, :string)
    field(:shipping_city, :string)
    field(:shipping_country, :string)
  end
end
