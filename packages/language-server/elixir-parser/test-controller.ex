defmodule TestWeb.PageController do
  use TestWeb, :controller

  def index(conn, _params) do
    user = get_user()
    posts = list_posts()

    render(conn, :index, user: user, posts: posts, page_title: "Home")
  end

  def show(conn, %{"id" => id}) do
    post = get_post(id)
    render(conn, :show, post: post)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def custom(conn, _params) do
    render(conn, TestWeb.CustomView, :custom, data: "test")
  end

  defp get_user do
    %{name: "Test User"}
  end

  defp get_post(id) do
    %{id: id, title: "Test Post"}
  end

  defp list_posts do
    [%{id: 1, title: "Post 1"}, %{id: 2, title: "Post 2"}]
  end
end
