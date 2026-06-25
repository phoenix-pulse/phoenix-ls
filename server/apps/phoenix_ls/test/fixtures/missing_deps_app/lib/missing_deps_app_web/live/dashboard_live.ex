defmodule MissingDepsAppWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, assign(socket, :title, "Missing deps")}

  def handle_event("retry", _params, socket), do: {:noreply, assign(socket, :retried, true)}

  def render(assigns) do
    ~H"""
    <button phx-click="retry">{@title}</button>
    """
  end
end
