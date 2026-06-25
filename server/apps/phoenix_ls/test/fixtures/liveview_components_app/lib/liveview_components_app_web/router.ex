defmodule LiveviewComponentsAppWeb.Router do
  use Phoenix.Router

  scope "/", LiveviewComponentsAppWeb do
    pipe_through(:browser)

    live("/", PageLive)
    get("/pages/:id", PageController, :show)
    resources("/products", ProductController, only: [:index, :show])
    forward("/mailbox", MailboxPlug, init_opts: [path: "/dev/mailbox"])

    scope "/admin" do
      pipe_through(:require_admin)

      live_session :admin do
        live("/products/:id", Admin.ProductLive, :show)
      end
    end
  end
end
