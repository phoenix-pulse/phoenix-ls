defmodule LiveviewComponentsAppWeb.Admin.ProductLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, assign(socket, :product, nil)}

  def handle_event("archive-product", _params, socket) do
    {:noreply, assign(socket, :archived, true)}
  end

  def render(assigns), do: ~H"<section>{@product}</section>"
end
