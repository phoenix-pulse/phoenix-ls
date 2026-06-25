defmodule Phoenix18ComplexApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_1_8_complex_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:ecto_sql, "~> 3.12"}
    ]
  end
end
