# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations do
  @moduledoc """
  Functions to setup Carbonite audit trails in your migrations.
  """

  use Ecto.Migration

  @default_prefix Application.compile_env!(:carbonite, :default_prefix)
  @default_table_prefix "public"

  @type carbonite_option :: {:prefix, String.t()}
  @type trigger_option :: {:table_prefix, String.t()} | {:carbonite_prefix, String.t()}
  @type trigger_config_option :: {:excluded_columns, [String.t()]}
  @type table_name :: String.t()

  @doc """
  Install a Carbonite audit trail.

  ## Options

  * `prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @spec install() :: :ok
  @spec install([carbonite_option()]) :: :ok
  def install(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)

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
      add(:old, :jsonb)
      add(:new, :jsonb)
    end

    create(index("changes", [:transaction_id], prefix: prefix))

    # ---------------- Triggers ------------------

    create table("triggers", primary_key: false, prefix: prefix) do
      add(:id, :bigserial, null: false, primary_key: true)
      add(:table_prefix, :string, null: false)
      add(:table_name, :string, null: false)
      add(:excluded_columns, {:array, :string}, null: false, default: [])

      timestamps()
    end

    create(
      index("triggers", [:table_prefix, :table_name],
        name: "table_index",
        unique: true,
        include: [:excluded_columns],
        prefix: prefix
      )
    )

    # ------------- Capture Function -------------

    """
    CREATE FUNCTION #{prefix}.capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      change_row #{prefix}.changes;
      trigger_row #{prefix}.triggers;
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
        NULL,
        NULL
      );

      /* fill in changed data */
      IF (TG_OP = 'UPDATE') THEN
        change_row.old = to_jsonb(OLD.*) - trigger_row.excluded_columns;
        change_row.new = to_jsonb(NEW.*) - trigger_row.excluded_columns;

        IF change_row.old = change_row.new THEN
          /* All changed fields are ignored. Skip this update. */
          RETURN NULL;
        END IF;
      ELSIF (TG_OP = 'DELETE') THEN
        change_row.old = to_jsonb(OLD.*) - trigger_row.excluded_columns;
      ELSIF (TG_OP = 'INSERT') THEN
        change_row.new = to_jsonb(NEW.*) - trigger_row.excluded_columns;
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
  Installs a change capture trigger on a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the Carbonite audit trail, defaults to `"carbonite_default"`
  * `excluded_columns` is a list of columns to exclude from change captures
  """
  @spec install_trigger(table_name()) :: :ok
  @spec install_trigger(table_name(), [trigger_option() | trigger_config_option()]) :: :ok
  def install_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, @default_prefix)

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
  * `carbonite_prefix` is the schema of the Carbonite audit trail, defaults to `"carbonite_default"`
  * `excluded_columns` is a list of columns to exclude from change captures
  """
  @spec configure_trigger(table_name()) :: :ok
  @spec configure_trigger(table_name(), [trigger_option() | trigger_config_option()]) :: :ok
  def configure_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, @default_prefix)

    excluded_columns =
      opts
      |> Keyword.get(:excluded_columns, [])
      |> Enum.map(&"\"#{&1}\"")
      |> Enum.join(",")

    """
    INSERT INTO #{carbonite_prefix}.triggers (
      table_prefix, table_name, excluded_columns, inserted_at, updated_at
    ) VALUES (
      '#{table_prefix}', '#{table_name}', '{#{excluded_columns}}', NOW(), NOW()
    )
    ON CONFLICT (table_prefix, table_name) DO
    UPDATE SET
      excluded_columns = excluded.excluded_columns,
      updated_at = excluded.updated_at;
    """
    |> squish_and_execute()
  end

  @doc """
  Removes a change capture trigger from a table.

  ## Options

  * `table_prefix` is the name of the schema the table lives in
  * `carbonite_prefix` is the schema of the Carbonite audit trail, defaults to `"carbonite_default"`
  """
  @spec drop_trigger(table_name()) :: :ok
  @spec drop_trigger(table_name(), [trigger_option()]) :: :ok
  def drop_trigger(table_name, opts \\ []) do
    table_prefix = Keyword.get(opts, :table_prefix, @default_table_prefix)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, @default_prefix)

    """
    DROP TRIGGER capture_changes_into_#{carbonite_prefix}_trigger
    ON #{table_prefix}.#{table_name};
    """
    |> squish_and_execute()

    :ok
  end

  # Removes surrounding and consecutive whitespace from SQL to improve readability in logs.
  defp squish_and_execute(statement) do
    statement
    |> String.replace(~r/[[:space:]]+/, " ")
    |> String.trim()
    |> execute()
  end
end
