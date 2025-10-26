defmodule TestWeb.UserLive.Index do
  use Phoenix.LiveView

  def handle_event("delete", %{"id" => id}, socket) do
    {:noreply, socket}
  end

  def handle_event("edit", params, socket) do
    {:noreply, socket}
  end

  defp handle_event(:private_event, _params, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh, socket) do
    {:noreply, socket}
  end

  def handle_info({:update, data}, socket) do
    {:noreply, socket}
  end

  def handle_info("string_message", socket) do
    {:noreply, socket}
  end
end
