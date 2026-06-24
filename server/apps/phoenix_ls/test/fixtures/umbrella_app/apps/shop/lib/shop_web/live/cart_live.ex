defmodule ShopWeb.CartLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div id="cart">Cart</div>
    """
  end
end
