defmodule PhoenixLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_ls,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: PhoenixLS.CLI],
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PhoenixLS.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gen_lsp, "~> 0.11"},
      {:sourceror, "~> 1.12", only: [:dev, :test]},
      {:file_system, "~> 1.1", optional: true}
    ]
  end
end
