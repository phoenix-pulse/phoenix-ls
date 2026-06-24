defmodule Phoenix18AppWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, assign(socket, :title, "Dashboard")}

  def handle_event("refresh", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Phoenix18AppWeb.CoreComponents.panel title={@title} />
    """
  end
end
