defmodule Phoenix18ComplexAppWeb.ProductController do
  use Phoenix18ComplexAppWeb, :controller

  plug :load_current_user

  def index(conn, _params) do
    products = [%{id: 1, name: "Desk", sku: "DSK"}]

    conn
    |> assign(:products, products)
    |> put_layout(html: :root)
    |> render(:index, page_title: "Products")
  end

  def show(conn, %{"id" => id}) do
    product = %{id: id, name: "Desk", sku: "DSK"}

    render(assign(conn, :product, product), :show, audit: true)
  end

  defp load_current_user(conn, _opts) do
    assign(conn, :current_user, %{email: "admin@example.com"})
  end
end
