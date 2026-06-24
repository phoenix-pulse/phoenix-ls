defmodule LiveviewComponentsAppWeb.PageLive do
  use Phoenix.LiveView

  import LiveviewComponentsAppWeb.CoreComponents

  def mount(_params, _session, socket), do: {:ok, assign(socket, :products, [])}

  def handle_event("select-product", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, id)}
  end

  def render(assigns) do
    ~H"""
    <.button label="Select" kind={:secondary}>
      <:actions icon="check" />
    </.button>
    """
  end
end
