import Config

if config_env() in [:dev, :test] do
  config :carbonite, Carbonite.TestRepo,
    database: "carbonite_test_repo",
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    types: Carbonite.PostgrexTypes

  config :carbonite, ecto_repos: [Carbonite.TestRepo]
end
