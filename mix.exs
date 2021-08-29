# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :carbonite,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),

      # hex.pm
      package: package(),
      description:
        "Change-Data-Capture: Based on triggers, emphasizing transactions, including outbox",

      # hexdocs.pm
      name: "Carbonite",
      source_url: "https://github.com/bitcrowd/carbonite",
      homepage_url: "https://github.com/bitcrowd/carbonite",
      docs: [
        main: "Carbonite",
        extras: ["README.md", "CHANGELOG.md": [title: "Changelog"]],
        source_ref: "v#{@version}",
        source_url: "https://github.com/bitcrowd/carbonite",
        formatters: ["html"]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["@bitcrowd"],
      licenses: ["Apache-2.0"],
      links: %{github: "https://github.com/bitcrowd/carbonite"}
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.6"},
      {:jason, "~> 1.2"},
      {:postgrex, ">= 0.0.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.24.1", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      lint: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --format dialyxir"
      ]
    ]
  end
end
