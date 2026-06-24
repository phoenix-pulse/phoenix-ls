defmodule Phoenix17AppWeb.Router do
  use Phoenix.Router

  scope "/", Phoenix17AppWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/products", ProductLive.Index, :index
  end
end
