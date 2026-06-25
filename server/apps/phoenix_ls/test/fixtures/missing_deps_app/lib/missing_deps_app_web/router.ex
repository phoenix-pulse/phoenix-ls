defmodule MissingDepsAppWeb.Router do
  use Phoenix.Router

  scope "/", MissingDepsAppWeb do
    pipe_through(:browser)

    live("/dashboard", DashboardLive)
  end
end
