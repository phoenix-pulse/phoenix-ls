defmodule ShopWeb.Router do
  use Phoenix.Router

  scope "/", ShopWeb do
    pipe_through :browser

    live "/cart", CartLive
  end
end
