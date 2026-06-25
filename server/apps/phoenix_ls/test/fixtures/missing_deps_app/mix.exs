defmodule MissingDepsApp.MixProject do
  use Mix.Project

  def project do
    [app: :missing_deps_app, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:missing_phoenix_dep, "~> 9.9"}
    ]
  end
end
