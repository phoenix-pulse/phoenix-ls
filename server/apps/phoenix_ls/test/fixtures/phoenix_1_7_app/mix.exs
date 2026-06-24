defmodule Phoenix17App.MixProject do
  use Mix.Project

  def project do
    [app: :phoenix_1_7_app, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"}
    ]
  end
end
