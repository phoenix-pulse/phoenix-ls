defmodule LiveviewComponentsAppWeb.Router do
  use Phoenix.Router

  scope "/", LiveviewComponentsAppWeb do
    pipe_through(:browser)

    live("/", PageLive)
    get("/pages/:id", PageController, :show)

    scope "/admin" do
      pipe_through(:require_admin)

      live("/products/:id", Admin.ProductLive, :show)
    end
  end
end
