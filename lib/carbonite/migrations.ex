# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations do
  @moduledoc """
  Functions to setup Carbonite audit trails in your migrations.
  """

  @moduledoc since: "0.1.0"

  use Ecto.Migration
  import Carbonite, only: [default_prefix: 0]
  import Carbonite.Migrations.Helper

  @type patch :: non_neg_integer()
  @type prefix :: binary()
  @type table_name :: binary() | atom()

  # --------------------------------- patch levels ---------------------------------

  @initial_patch 1
  @current_patch 5

  @doc false
  @spec initial_patch :: non_neg_integer()
  def initial_patch, do: @initial_patch

  @doc false
  @spec current_patch :: non_neg_integer()
  def current_patch, do: @current_patch

  # --------------------------------- main schema ----------------------------------

  @type up_option :: {:carbonite_prefix, prefix()}

  @doc """
  Runs one of Carbonite's migrations.

  ## Migration patchlevels

  Make sure that you run all migrations in your host application.

  * Initial patch: #{@initial_patch}
  * Current patch: #{@current_patch}

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec up(patch()) :: :ok
  @spec up(patch(), [up_option()]) :: :ok
  def up(patch, opts \\ []) when is_integer(patch) and is_list(opts) do
    change(:up, patch, opts)
  end

  @type down_option :: {:carbonite_prefix, prefix()} | {:drop_schema, boolean()}

  @doc """
  Rollback a migration.

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `drop_schema` controls whether the initial migration deletes the schema during rollback
  """
  @doc since: "0.4.0"
  @spec down(patch()) :: :ok
  @spec down(patch(), [down_option()]) :: :ok
  def down(patch, opts \\ []) when is_integer(patch) and is_list(opts) do
    change(:down, patch, opts)
  end

  defp change(direction, patch, opts) when is_integer(patch) do
    module = Module.concat([__MODULE__, "V#{patch}"])

    apply(module, direction, [opts])
  end

  # ------------------------------- trigger setup ----------------------------------

  @default_table_prefix "public"

  @type trigger_option :: {:table_prefix, prefix()} | {:carbonite_prefix, prefix()}

  @doc """
  Installs a change capture trigger on a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec create_trigger(table_name()) :: :ok
  @spec create_trigger(table_name(), [trigger_option()]) :: :ok
  def create_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    CREATE TRIGGER capture_changes_into_#{carbonite_prefix}_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON #{table_prefix}.#{table_name}
    FOR EACH ROW
    EXECUTE PROCEDURE #{carbonite_prefix}.capture_changes();
    """
    |> squish_and_execute()

    """
    INSERT INTO #{carbonite_prefix}.triggers (
      id,
      table_prefix,
      table_name,
      inserted_at,
      updated_at
    ) VALUES (
      NEXTVAL('#{carbonite_prefix}.triggers_id_seq'),
      '#{table_prefix}',
      '#{table_name}',
      NOW(),
      NOW()
    );
    """
    |> squish_and_execute()

    :ok
  end

  @doc """
  Removes a change capture trigger from a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec drop_trigger(table_name()) :: :ok
  @spec drop_trigger(table_name(), [trigger_option()]) :: :ok
  def drop_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    DELETE FROM #{carbonite_prefix}.triggers
    WHERE table_prefix = '#{table_prefix}'
    AND table_name = '#{table_name}';
    """
    |> squish_and_execute()

    """
    DROP TRIGGER capture_changes_into_#{carbonite_prefix}_trigger
    ON #{table_prefix}.#{table_name};
    """
    |> squish_and_execute()

    :ok
  end

  @type trigger_config_key :: :table_prefix | :primary_key_columns | :excluded_columns | :mode

  @doc """
  Allows to update a trigger configuration option for a given table.

  This function builds an SQL UPDATE statement that can be used within a database migration to
  update a setting stored in Carbonite's `triggers` table without using the `Carbonite.Trigger`
  schema or other application-level code that is prone to change over time. This helps to ensure
  that your data migrations continue to function, regardless of future updates to Carbonite.

  ## Configuration values

  * `primary_key_columns` is a list of columns that form the primary key of the table
                          (defaults to `["id"]`, set to `[]` to disable)
  * `excluded_columns` is a list of columns to exclude from change captures
  * `filtered_columns` is a list of columns that appear as '[FILTERED]' in the data
  * `store_changed_from` is a boolean defining whether the `changed_from` field should be filled
  * `mode` is either `:capture` or `:ignore` and defines the default behaviour of the trigger

  ## Example

      Carbonite.Migrations.put_trigger_config("rabbits", :excluded_columns, ["name"])

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec put_trigger_config(table_name(), trigger_config_key(), any(), [trigger_option()]) :: :ok
  def put_trigger_config(table_name, key, value, opts \\ [])

  def put_trigger_config(table_name, key, value, opts)
      when key in [:primary_key_columns, :excluded_columns, :filtered_columns] do
    do_put_trigger_config(table_name, key, column_list(value), opts)
  end

  def put_trigger_config(table_name, :mode, value, opts) when value in [:capture, :ignore] do
    do_put_trigger_config(table_name, :mode, "'#{value}'", opts)
  end

  def put_trigger_config(table_name, :store_changed_from, value, opts) when is_boolean(value) do
    do_put_trigger_config(table_name, :store_changed_from, value, opts)
  end

  defp do_put_trigger_config(table_name, field, value, opts) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    UPDATE #{carbonite_prefix}.triggers
    SET #{field} = #{value}, updated_at = NOW()
    WHERE table_prefix = '#{table_prefix}'
    AND table_name = '#{table_name}';
    """
    |> squish_and_execute()

    :ok
  end

  # ------------------------------- outbox setup -----------------------------------

  @type outbox_name :: String.t()
  @type outbox_option :: {:carbonite_prefix, prefix()}

  @doc """
  Inserts an outbox record into the database.

  ## Options

  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec create_outbox(outbox_name()) :: :ok
  @spec create_outbox(outbox_name(), [outbox_option()]) :: :ok
  def create_outbox(outbox_name, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    INSERT INTO #{carbonite_prefix}.outboxes (
      name,
      inserted_at,
      updated_at
    ) VALUES (
      '#{outbox_name}',
      NOW(),
      NOW()
    );
    """
    |> squish_and_execute()

    :ok
  end

  @doc """
  Removes an outbox record.

  ## Options

  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec drop_outbox(outbox_name()) :: :ok
  @spec drop_outbox(outbox_name(), [outbox_option()]) :: :ok
  def drop_outbox(outbox_name, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    DELETE FROM #{carbonite_prefix}.outboxes
    WHERE name = '#{outbox_name}';
    """
    |> squish_and_execute()

    :ok
  end

  # ------------------------------ data migration s---------------------------------

  @type insert_migration_transaction_option :: {:carbonite_prefix, prefix()} | {:meta, map()}

  @doc """
  Inserts a transaction for a data migration.

  The transaction's `meta` attribute is populated with

      {"type": "migration", direction: "up"}

  ... and additionally the `name` from the parameters.

  ## Example

      defmodule MyApp.Repo.Migrations.SomeDataMigration do
        use Ecto.Migration

        import Carbonite.Migrations

        def change do
          insert_migration_transaction()

          execute("UPDATE ...", "...")
        end
      end

  This works the same for `up/0`/`down/0`-style migrations:

      defmodule MyApp.Repo.Migrations.SomeDataMigration do
        use Ecto.Migration

        import Carbonite.Migrations

        def up do
          insert_migration_transaction("some-data-migrated")

          execute("INSERT ...")
        end

        def down do
          insert_migration_transaction("some-data-rolled-back")

          execute("DELETE ...")
        end
      end

  ## Options

  * `carbonite_prefix` is the schema of the audit trail, defaults to `"carbonite_default"`
  * `meta` is a map with additional meta information to store on the transaction
  """
  @spec insert_migration_transaction(name :: String.t(), [insert_migration_transaction_option()]) ::
          :ok
  def insert_migration_transaction(name, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())
    meta = Keyword.get(opts, :meta, %{})

    meta =
      %{type: "migration", direction: direction(), name: to_string(name)}
      |> Map.merge(meta)
      |> Jason.encode!()

    statement =
      """
      INSERT INTO #{carbonite_prefix}.transactions (meta, inserted_at)
      VALUES ('#{meta}'::jsonb, NOW());
      """
      |> squish()

    # Needed because `change/0` requires a rollback statement. In our case irrelevant, as we're
    # inserting a transaction in both directions (and the `direction` value is set dynamically).
    execute(statement, statement)
  end

  @doc """
  Defines a `c:Ecto.Migration.after_begin/0` implementation for a data migration.

  See `insert_migration_transaction/1` for options.

  This determines the `name` of the transaction from the migration's module name.

       {"direction": "up","name": "my_app/repo/migrations/example", "type": "migration"}

  ## Example

      defmodule MyApp.Repo.Migrations.SomeDataMigration do
        use Ecto.Migration

        import Carbonite.Migrations
        insert_migration_transaction_after_begin()

        def change do
          execute("UPDATE ...")
        end
      end

  Alternatively, if you define your own migration template module:

      defmodule MyApp.Migration do
        defmacro __using__ do
          quote do
            use Ecto.Migration

            import Carbonite.Migrations
            insert_migration_transaction_after_begin()
          end
        end
      end
  """
  @doc since: "0.5.0"
  defmacro insert_migration_transaction_after_begin(opts \\ []) do
    opts = Keyword.take(opts, [:carbonite_prefix, :meta])

    quote do
      @behaviour Ecto.Migration

      @impl Ecto.Migration
      def after_begin do
        __MODULE__
        |> Macro.underscore()
        |> Carbonite.Migrations.insert_migration_transaction(unquote(opts))
      end
    end
  end
end
