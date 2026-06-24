defmodule BrokenSyntaxAppWeb.BrokenLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div><%= @title %></div>
    """

end
