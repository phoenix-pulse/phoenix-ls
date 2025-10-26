defmodule MyAppWeb.PageHTML do
  use MyAppWeb, :html

  embed_templates "page_html/*"

  def home(assigns) do
    ~H"""
    <h1>Welcome</h1>
    """
  end

  def about(assigns) do
    ~H"""
    <h1>About</h1>
    """
  end

  # This should be skipped (private)
  defp _helper(assigns) do
    ~H"<span>Helper</span>"
  end
end
