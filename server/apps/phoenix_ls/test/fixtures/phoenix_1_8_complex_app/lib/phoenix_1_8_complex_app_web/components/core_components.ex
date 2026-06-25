defmodule Phoenix18ComplexAppWeb.CoreComponents do
  use Phoenix.Component

  attr :title, :string, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header>
      <h1><%= @title %></h1>
      <p :if={@subtitle != []}><%= render_slot(@subtitle) %></p>
      <div :if={@actions != []}><%= render_slot(@actions) %></div>
    </header>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: nil
  attr :type, :string, default: "text"

  def input(assigns) do
    ~H"""
    <label>
      <span><%= @label %></span>
      <input id={@field.id} name={@field.name} type={@type} value={@field.value} />
    </label>
    """
  end
end
