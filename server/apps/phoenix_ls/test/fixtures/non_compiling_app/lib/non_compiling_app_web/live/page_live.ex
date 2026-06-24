defmodule NonCompilingAppWeb.PageLive do
  use Phoenix.LiveView

  def render(assigns) do
    MissingDependency.call()

    ~H"""
    <div>Non compiling but parseable</div>
    """
  end
end
