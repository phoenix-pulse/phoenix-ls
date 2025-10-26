defmodule TestWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TestWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about
    post "/contact", PageController, :contact

    live "/users", UserLive.Index, :index
    live "/users/:id", UserLive.Show, :show

    resources "/posts", PostController
    resources "/products", ProductController, only: [:index, :show]
    resources "/admin/users", AdminUserController, except: [:delete]
  end

  scope "/api", TestWeb, as: :api do
    pipe_through :api

    get "/status", ApiController, :status
    resources "/items", ItemController

    forward "/graphql", Absinthe.Plug
  end
end
