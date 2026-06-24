defmodule Shop.MixProject do
  use Mix.Project

  def project do
    [app: :shop, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"}
    ]
  end
end
