defmodule LargeStressAppWeb.Router do
  use Phoenix.Router

  scope "/", LargeStressAppWeb do
    pipe_through(:browser)

    live("/dashboard", DashboardLive)
    resources("/orders", OrderController)
    get("/reports/0", ReportController, :show_0)
    get("/reports/1", ReportController, :show_1)
    get("/reports/2", ReportController, :show_2)
    get("/reports/3", ReportController, :show_3)
    get("/reports/4", ReportController, :show_4)
    get("/reports/5", ReportController, :show_5)
    get("/reports/6", ReportController, :show_6)
    get("/reports/7", ReportController, :show_7)
    get("/reports/8", ReportController, :show_8)
    get("/reports/9", ReportController, :show_9)
    get("/reports/10", ReportController, :show_10)
    get("/reports/11", ReportController, :show_11)
    get("/reports/12", ReportController, :show_12)
    get("/reports/13", ReportController, :show_13)
    get("/reports/14", ReportController, :show_14)
    get("/reports/15", ReportController, :show_15)
    get("/reports/16", ReportController, :show_16)
    get("/reports/17", ReportController, :show_17)
    get("/reports/18", ReportController, :show_18)
    get("/reports/19", ReportController, :show_19)
  end
end
