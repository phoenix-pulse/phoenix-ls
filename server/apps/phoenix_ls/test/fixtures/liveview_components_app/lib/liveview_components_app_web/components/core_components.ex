defmodule LiveviewComponentsAppWeb.CoreComponents do
  use Phoenix.Component

  attr :label, :string, required: true, doc: "Button label"
  attr :kind, :atom, default: :primary
  slot :inner_block
  slot :actions do
    attr :icon, :string
  end

  def button(assigns) do
    ~H"""
    <button data-kind={@kind}>
      <%= @label %>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
