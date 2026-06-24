defmodule Phoenix18AppWeb.Router do
  use Phoenix.Router

  scope "/", Phoenix18AppWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/dashboard", DashboardLive
  end
end
