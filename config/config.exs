# SPDX-License-Identifier: Apache-2.0

import Config

if config_env() in [:dev, :test] do
  config :carbonite, Carbonite.TestRepo,
    database: "carbonite_#{config_env()}",
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    priv: "test/support/test_repo"

  config :carbonite, ecto_repos: [Carbonite.TestRepo]
end

if config_env() == :test do
  # Set to :debug to see SQL logs.
  config :logger, level: :info

  config :carbonite, Carbonite.TestRepo, pool: Ecto.Adapters.SQL.Sandbox
end
