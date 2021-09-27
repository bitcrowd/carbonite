# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations do
  @moduledoc """
  Functions to setup Carbonite transaction logs in your migrations.
  """

  use Ecto.Migration
  import Carbonite, only: [default_prefix: 0]

  @type prefix :: binary() | atom()
  @type table_name :: binary() | atom()
  @type column_name :: binary()

  @type schema_option :: {:prefix, prefix()}

  @doc """
  Installs a Carbonite transaction log.

  ## Options

  * `prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
  """
  @spec install_schema() :: :ok
  @spec install_schema([schema_option()]) :: :ok
  def install_schema(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, default_prefix())

    # ---------------- Schema --------------------

    execute("CREATE SCHEMA IF NOT EXISTS #{prefix}")

    # -------------- Transactions ----------------

    create table("transactions", primary_key: false, prefix: prefix) do
      add(:id, :xid8, null: false, primary_key: true)
      add(:meta, :map, null: false, default: %{})
      add(:processed_at, :utc_datetime_usec)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(
      index("transactions", [:inserted_at],
        where: "processed_at IS NULL",
        prefix: prefix
      )
    )

    """
    CREATE FUNCTION #{prefix}.set_transaction_id() RETURNS TRIGGER AS
    $body$
    BEGIN
      NEW.id = pg_current_xact_id();
      RETURN NEW;
    END
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()

    """
    CREATE TRIGGER set_transaction_id_trigger
    BEFORE INSERT
    ON #{prefix}.transactions
    FOR EACH ROW
    EXECUTE PROCEDURE #{prefix}.set_transaction_id();
    """
    |> squish_and_execute()

    # ---------------- Changes -------------------

    execute("CREATE TYPE #{prefix}.change_op AS ENUM('insert', 'update', 'delete');")

    create table("changes", primary_key: false, prefix: prefix) do
      add(:id, :bigserial, null: false, primary_key: true)

      add(
        :transaction_id,
        references(:transactions,
          on_delete: :delete_all,
          on_update: :update_all,
          type: :xid8,
          prefix: prefix
        ),
        null: false
      )

      add(:op, :"#{prefix}.change_op", null: false)
      add(:table_prefix, :string, null: false)
      add(:table_name, :string, null: false)
      add(:table_pk, {:array, :string}, null: true)
      add(:data, :jsonb, null: false)
      add(:changed, {:array, :string}, null: false)
    end

    create(index("changes", [:transaction_id], prefix: prefix))
    create(index("changes", [:table_prefix, :table_name, :table_pk], prefix: prefix))

    # ---------------- Triggers ------------------

    create table("triggers", primary_key: false, prefix: prefix) do
      add(:id, :bigserial, null: false, primary_key: true)
      add(:table_prefix, :string, null: false)
      add(:table_name, :string, null: false)
      add(:primary_key_columns, {:array, :string}, null: false, default: [])
      add(:excluded_columns, {:array, :string}, null: false, default: [])

      timestamps()
    end

    create(
      index("triggers", [:table_prefix, :table_name],
        name: "table_index",
        unique: true,
        include: [:primary_key_columns, :excluded_columns],
        prefix: prefix
      )
    )

    # ------------- Capture Function -------------

    """
    CREATE FUNCTION #{prefix}.capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      trigger_row #{prefix}.triggers;
      change_row #{prefix}.changes;
      pk_source RECORD;
      pk_col VARCHAR;
      pk_col_val VARCHAR;
      pk_col_val_arr VARCHAR[] := '{}';
      old_field RECORD;
    BEGIN
      /* load trigger config */
      SELECT *
        INTO trigger_row
        FROM #{prefix}.triggers
        WHERE table_prefix = TG_TABLE_SCHEMA AND table_name = TG_TABLE_NAME;

      /* instantiate change row */
      change_row = ROW(
        NEXTVAL('#{prefix}.changes_id_seq'),
        pg_current_xact_id(),
        LOWER(TG_OP::TEXT),
        TG_TABLE_SCHEMA::TEXT,
        TG_TABLE_NAME::TEXT,
        '{}',
        NULL,
        '{}'
      );

      /* build table_pk */
      IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
        pk_source := NEW;
      ELSIF (TG_OP = 'DELETE') THEN
        pk_source := OLD;
      END IF;

      FOREACH pk_col IN ARRAY trigger_row.primary_key_columns LOOP
        EXECUTE 'SELECT $1.' || pk_col || '::text' USING pk_source INTO pk_col_val;
        change_row.table_pk := change_row.table_pk || pk_col_val;
      END LOOP;

      /* fill in changed data */
      IF (TG_OP = 'UPDATE') THEN
        change_row.data = to_jsonb(NEW.*) - trigger_row.excluded_columns;

        FOR old_field IN SELECT * FROM jsonb_each(to_jsonb(OLD.*) - trigger_row.excluded_columns) LOOP
          IF NOT change_row.data @> jsonb_build_object(old_field.key, old_field.value)
             THEN change_row.changed := change_row.changed || old_field.key::VARCHAR;
          END IF;
        END LOOP;

        IF change_row.changed = '{}' THEN
          /* All changed fields are ignored. Skip this update. */
          RETURN NULL;
        END IF;
      ELSIF (TG_OP = 'DELETE') THEN
        change_row.data = to_jsonb(OLD.*) - trigger_row.excluded_columns;
      ELSIF (TG_OP = 'INSERT') THEN
        change_row.data = to_jsonb(NEW.*) - trigger_row.excluded_columns;
      END IF;

      /* insert, fail gracefully unless transaction record present */
      BEGIN
        INSERT INTO #{prefix}.changes VALUES (change_row.*);
      EXCEPTION WHEN foreign_key_violation THEN
        RAISE '% on table %.% without prior INSERT into #{prefix}.transactions',
          TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = 'foreign_key_violation';
      END;

      RETURN NULL;
    END;
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()

    :ok
  end

  @doc """
  Removes a Carbonite transaction log from the database.

  ## Options

  * `prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
  """
  @spec drop_schema() :: :ok
  @spec drop_schema([schema_option()]) :: :ok
  def drop_schema(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, default_prefix())

    execute("DROP SCHEMA #{prefix};")
  end

  @default_table_prefix "public"

  @type trigger_option :: {:table_prefix, prefix()} | {:carbonite_prefix, prefix()}
  @type trigger_config_option ::
          {:primary_key_columns, [column_name()]} | {:excluded_columns, [column_name()]}

  @doc """
  Installs a change capture trigger on a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the transaction log, defaults to `"carbonite_default"`
  * `primary_key_columns` is a list of columns that form the primary key of the table
                          (defaults to `["id"]`, set to `[]` or nil to disable)
  * `excluded_columns` is a list of columns to exclude from change captures
  """
  @spec install_trigger(table_name()) :: :ok
  @spec install_trigger(table_name(), [trigger_option() | trigger_config_option()]) :: :ok
  def install_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    execute("""
    CREATE TRIGGER capture_changes_into_#{carbonite_prefix}_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON #{table_prefix}.#{table_name}
    FOR EACH ROW
    EXECUTE PROCEDURE #{carbonite_prefix}.capture_changes();
    """)

    configure_trigger(table_name, opts)

    :ok
  end

  @doc """
  Alters a triggers configuration for a given table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the transaction log, defaults to `"carbonite_default"`
  * `primary_key_columns` is a list of columns that together build the primary key of the table
  * `excluded_columns` is a list of columns to exclude from change captures
  """
  @spec configure_trigger(table_name()) :: :ok
  @spec configure_trigger(table_name(), [trigger_option() | trigger_config_option()]) :: :ok
  def configure_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    primary_key_columns = column_list(opts[:primary_key_columns])
    excluded_columns = column_list(opts[:excluded_columns])

    """
    INSERT INTO #{carbonite_prefix}.triggers (
      table_prefix, table_name, primary_key_columns, excluded_columns, inserted_at, updated_at
    ) VALUES (
      '#{table_prefix}', '#{table_name}', '#{primary_key_columns}', '#{excluded_columns}', NOW(), NOW()
    )
    ON CONFLICT (table_prefix, table_name) DO
    UPDATE SET
      primary_key_columns = excluded.primary_key_columns,
      excluded_columns = excluded.excluded_columns,
      updated_at = excluded.updated_at;
    """
    |> squish_and_execute()
  end

  @doc """
  Removes a change capture trigger from a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the transaction log, defaults to `"carbonite_default"`
  """
  @spec drop_trigger(table_name()) :: :ok
  @spec drop_trigger(table_name(), [trigger_option()]) :: :ok
  def drop_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    """
    DROP TRIGGER capture_changes_into_#{carbonite_prefix}_trigger
    ON #{table_prefix}.#{table_name};
    """
    |> squish_and_execute()

    :ok
  end

  # Joins a list of atoms/strings to a `{'bar', 'foo', ...}` (ordered) SQL array expression.
  defp column_list(nil), do: "{}"
  defp column_list(value), do: "{#{do_column_list(value)}}"

  defp do_column_list(value) do
    value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.map(&"\"#{&1}\"")
    |> Enum.join(",")
  end

  # Removes surrounding and consecutive whitespace from SQL to improve readability in console.
  defp squish_and_execute(statement) do
    statement
    |> String.replace(~r/[[:space:]]+/, " ")
    |> String.trim()
    |> execute()
  end
end
