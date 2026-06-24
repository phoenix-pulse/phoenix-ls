defmodule LiveviewComponentsApp.MixProject do
  use Mix.Project

  def project do
    [app: :liveview_components_app, version: "0.1.0", deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:ecto, "~> 3.12"}
    ]
  end
end
