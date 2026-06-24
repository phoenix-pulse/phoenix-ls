defmodule Phoenix18AppWeb.CoreComponents do
  use Phoenix.Component

  attr :title, :string, required: true

  def panel(assigns) do
    ~H"""
    <section><h2><%= @title %></h2></section>
    """
  end
end
