defmodule Phoenix.Component.Builtins do
  @moduledoc """
  Synthetic definitions for built-in Phoenix components.

  The actual implementations live in Phoenix itself; these stubs exist so that
  editors can jump to a helpful location when navigating from HEEx templates.
  """

  @doc """
  Synthetic placeholder for `Phoenix.Component.link/1`.
  """
  # slot :inner_block
  def link(assigns) do
    raise ArgumentError,
          "phoenix_component/link/1 is provided by Phoenix.Component at runtime"
  end

  @doc """
  Synthetic placeholder for `Phoenix.Component.live_patch/1`.
  """
  # slot :inner_block
  def live_patch(assigns) do
    raise ArgumentError,
          "phoenix_component/live_patch/1 is provided by Phoenix.Component at runtime"
  end

  @doc """
  Synthetic placeholder for `Phoenix.Component.live_redirect/1`.
  """
  # slot :inner_block
  def live_redirect(assigns) do
    raise ArgumentError,
          "phoenix_component/live_redirect/1 is provided by Phoenix.Component at runtime"
  end

  @doc """
  Synthetic placeholder for `Phoenix.Component.live_component/1`.
  """
  # slot :inner_block
  def live_component(assigns) do
    raise ArgumentError,
          "phoenix_component/live_component/1 is provided by Phoenix.Component at runtime"
  end

  @doc """
  Synthetic placeholder for `Phoenix.Component.form/1`.
  """
  # slot :inner_block
  # slot :actions
  def form(assigns) do
    raise ArgumentError,
          "phoenix_component/form/1 is provided by Phoenix.Component at runtime"
  end

  @doc """
  Synthetic placeholder for `Phoenix.Component.inputs_for/1`.
  """
  # slot :inner_block
  def inputs_for(assigns) do
    raise ArgumentError,
          "phoenix_component/inputs_for/1 is provided by Phoenix.Component at runtime"
  end
end
