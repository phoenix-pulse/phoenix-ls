defmodule Phoenix18ComplexAppWeb.Router do
  use Phoenix.Router

  scope "/", Phoenix18ComplexAppWeb do
    pipe_through :browser

    get "/sign-in", SessionController, :new
    resources "/products", ProductController, only: [:index, :show]
    resources "/products/:product_id/orders", OrderController, only: [:index]
    forward "/mailbox", MailboxPlug, init_opts: [path: "/dev/mailbox"]

    live "/orders", OrderLive.Index, :index
    live "/orders/upload", OrderLive.Upload, :index

    live_session :admin do
      live "/admin/orders/:id", OrderLive.Index, :show
    end
  end
end
