defmodule Phoenix17AppWeb.CoreComponents do
  use Phoenix.Component

  attr :product, :map, required: true
  slot :inner_block

  def product_card(assigns) do
    ~H"""
    <article><%= @product.name %><%= render_slot(@inner_block) %></article>
    """
  end
end
