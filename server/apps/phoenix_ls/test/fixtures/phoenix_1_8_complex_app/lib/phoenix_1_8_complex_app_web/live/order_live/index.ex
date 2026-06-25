defmodule Phoenix18ComplexAppWeb.OrderLive.Index do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:orders, [])
      |> assign(:form, Phoenix.Component.to_form(%{"lines" => [%{"sku" => ""}]}))
      |> start_async(:load_orders, fn -> [%{id: 1, number: "A-1"}] end)

    {:ok, socket, temporary_assigns: [orders: []]}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_async(:load_orders, {:ok, orders}, socket) do
    {:noreply, assign(socket, :orders, orders)}
  end

  def handle_event("filter-orders", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.live_component module={Phoenix18ComplexAppWeb.OrderLive.Upload} id="upload" />
    """
  end
end
