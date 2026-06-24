defmodule Phoenix17AppWeb.ProductLive.Index do
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, assign(socket, :products, [])}

  def handle_event("save", %{"product" => _params}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.product_card :for={product <- @products} product={product} />
    """
  end
end
