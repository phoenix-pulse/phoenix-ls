defmodule BrokenSyntaxApp.MixProject do
  use Mix.Project

  def project do
    [app: :broken_syntax_app, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [{:phoenix, "~> 1.8"}]
  end
end
