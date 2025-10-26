defmodule TestWeb.Components.Button do
  use Phoenix.Component

  @doc """
  A button component with various styles.
  """
  attr :variant, :string, values: ["primary", "secondary", "danger"], default: "primary"
  attr :size, :atom, values: [:sm, :md, :lg], default: :md
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, doc: "Additional HTML attributes"

  slot :inner_block, required: true, doc: "Button content"
  slot :icon, doc: "Optional icon slot"

  def button(assigns) do
    ~H"""
    <button class={[@variant, @size, @class]} disabled={@disabled} {@rest}>
      <%= if @icon do %>
        <%= render_slot(@icon) %>
      <% end %>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  A card component with header and footer.
  """
  attr :title, :string, required: true
  attr :variant, :string, values: ["default", "highlighted"], default: "default"

  slot :header
  slot :footer

  def card(assigns) do
    ~H"""
    <div class={["card", @variant]}>
      <%= if @header do %>
        <div class="card-header">
          <%= render_slot(@header) %>
        </div>
      <% end %>

      <div class="card-body">
        <h3><%= @title %></h3>
      </div>

      <%= if @footer do %>
        <div class="card-footer">
          <%= render_slot(@footer) %>
        </div>
      <% end %>
    </div>
    """
  end
end
