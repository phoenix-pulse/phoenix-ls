defmodule LargeStressAppWeb.CoreComponents do
  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:count, :integer, default: 0)
  slot(:inner_block)

  def panel(assigns) do
    ~H"""
    <section><h2>{@title}</h2>{render_slot(@inner_block)}</section>
    """
  end

  attr(:label, :string, required: true)
  def metric(assigns), do: ~H"<p>{@label}</p>"

  attr(:status, :atom, default: :ok)
  def badge(assigns), do: ~H"<span>{@status}</span>"

  attr(:rows, :list, default: [])

  def table(assigns),
    do: ~H"<table><tbody><tr :for={row <- @rows}><td>{row}</td></tr></tbody></table>"

  attr(:href, :string, required: true)
  def link_button(assigns), do: ~H"<a href={@href}>Open</a>"
end
