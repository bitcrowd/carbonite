# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MixProject do
  use Mix.Project

  @version "0.7.0"

  def project do
    [
      app: :carbonite,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [lint: :test],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :jason],
        plt_core_path: "_plts",
        plt_file: {:no_warn, "_plts/carbonite.plt"}
      ],

      # hex.pm
      package: package(),
      description: "Audit trails for Elixir/PostgreSQL based on triggers",

      # hexdocs.pm
      name: "Carbonite",
      source_url: "https://github.com/bitcrowd/carbonite",
      homepage_url: "https://github.com/bitcrowd/carbonite",
      docs: [
        main: "Carbonite",
        logo: ".logo_for_docs.png",
        extras: ["CHANGELOG.md": [title: "Changelog"], LICENSE: [title: "License"]],
        source_ref: "v#{@version}",
        source_url: "https://github.com/bitcrowd/carbonite",
        formatters: ["html"],
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
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
      {:postgrex, "~> 0.15 and >= 0.15.11"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "> 0.0.0", only: [:dev], runtime: false},
      {:junit_formatter, "~> 3.3", only: [:test]}
    ]
  end

  defp aliases do
    [
      lint: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --format dialyxir"
      ],
      "ecto.reset": [
        "ecto.drop",
        "ecto.create",
        "ecto.migrate"
      ]
    ]
  end
end
