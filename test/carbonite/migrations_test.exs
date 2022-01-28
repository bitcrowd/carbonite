# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MigrationsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  defmodule UnboxedTestRepo do
    use Ecto.Repo,
      otp_app: :carbonite,
      adapter: Ecto.Adapters.Postgres

    @impl Ecto.Repo
    def init(_context, config) do
      test_repo_config =
        :carbonite
        |> Application.fetch_env!(Carbonite.TestRepo)
        |> Keyword.delete(:pool)

      {:ok, Keyword.merge(config, test_repo_config)}
    end
  end

  defmodule InsertMigrato do
    use Ecto.Migration
    import Carbonite.Migrations

    insert_migration_transaction_after_begin()

    def up do
      execute("INSERT INTO rabbits (name, age) VALUES ('Migrato', 180)")
    end

    def down do
      execute("DELETE FROM rabbits WHERE name = 'Migrato'")
    end
  end

  setup do
    start_supervised!(UnboxedTestRepo)

    :ok
  end

  defp up_and_down_migration(migration, up_cb, down_cb) do
    capture_log(fn ->
      try do
        Ecto.Migrator.run(UnboxedTestRepo, [{0, migration}], :up, all: true)

        up_cb.()

        Ecto.Migrator.run(UnboxedTestRepo, [{0, migration}], :down, all: true)

        down_cb.()
      after
        # Cleanup. Here because `start_supervised!` stops the Repo too early for an `on_exit`.
        delete_all_transactions()
      end
    end)
  end

  defp select_all_transactions do
    UnboxedTestRepo.all(Carbonite.Query.transactions(preload: true))
  end

  defp delete_all_transactions do
    UnboxedTestRepo.delete_all(Carbonite.Query.transactions())
  end

  describe "insert_migration_transaction_after_begin/1" do
    test "makes the migration automatically insert a transaction" do
      up_and_down_migration(
        InsertMigrato,
        fn ->
          assert [
                   %{
                     changes: [%{op: :insert, table_name: "rabbits"}],
                     meta: %{
                       "direction" => "up",
                       "name" => "carbonite/migrations_test/insert_migrato",
                       "type" => "migration"
                     }
                   }
                 ] = select_all_transactions()
        end,
        fn ->
          assert [_, %{meta: %{"direction" => "down"}}] = select_all_transactions()
        end
      )
    end
  end
end
