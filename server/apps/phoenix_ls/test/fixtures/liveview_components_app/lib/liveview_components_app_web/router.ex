defmodule LiveviewComponentsAppWeb.Router do
  use Phoenix.Router

  scope "/", LiveviewComponentsAppWeb do
    pipe_through :browser

    live "/", PageLive
    get "/pages/:id", PageController, :show
  end
end
