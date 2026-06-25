defmodule LargeStressAppWeb.DashboardLive do
  use Phoenix.LiveView

  import LargeStressAppWeb.CoreComponents

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:title, "Stress dashboard")
      |> assign(:orders, [])
      |> assign(:refresh_count, 0)

    {:ok, socket}
  end

  def handle_event("refresh-0", _params, socket), do: refreshed(socket, 0)
  def handle_event("refresh-1", _params, socket), do: refreshed(socket, 1)
  def handle_event("refresh-2", _params, socket), do: refreshed(socket, 2)
  def handle_event("refresh-3", _params, socket), do: refreshed(socket, 3)
  def handle_event("refresh-4", _params, socket), do: refreshed(socket, 4)
  def handle_event("refresh-5", _params, socket), do: refreshed(socket, 5)
  def handle_event("refresh-6", _params, socket), do: refreshed(socket, 6)
  def handle_event("refresh-7", _params, socket), do: refreshed(socket, 7)
  def handle_event("refresh-8", _params, socket), do: refreshed(socket, 8)
  def handle_event("refresh-9", _params, socket), do: refreshed(socket, 9)

  def render(assigns) do
    ~H"""
    <.panel title={@title} count={@refresh_count}>
      <.metric label="Orders" />
      <.badge status={:ok} />
      <.table rows={@orders} />
      <.link_button href="/orders" />
      <button phx-click="refresh-0">Refresh</button>
    </.panel>
    """
  end

  defp refreshed(socket, count), do: {:noreply, assign(socket, :refresh_count, count)}
end
