defmodule Phoenix18ComplexAppWeb.OrderLive.Upload do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
  end

  def handle_event("save", _params, socket) do
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry -> {:ok, path} end)
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def render(assigns) do
    ~H"""
    <form phx-submit="save" phx-change="validate">
      <.live_file_input upload={@uploads.avatar} />
    </form>
    """
  end
end
