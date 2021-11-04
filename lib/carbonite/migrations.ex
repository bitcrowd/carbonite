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
  @current_patch 2

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

  * Initial patch: 1
  * Current patch: 2

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
      table_prefix,
      table_name,
      inserted_at,
      updated_at
    ) VALUES (
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
    do_put_trigger_config(table_name, :mode, value, opts)
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
end
