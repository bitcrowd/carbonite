# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V1 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()}

  @spec create_set_transaction_id_procedure(prefix()) :: :ok
  def create_set_transaction_id_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.set_transaction_id() RETURNS TRIGGER AS
    $body$
    BEGIN
      NEW.id = COALESCE(NEW.id, pg_current_xact_id());
      RETURN NEW;
    END
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()
  end

  @spec create_capture_changes_procedure(prefix()) :: :ok
  def create_capture_changes_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      trigger_row #{prefix}.triggers;
      change_row #{prefix}.changes;
      pk_source RECORD;
      col_name VARCHAR;
      pk_col_val VARCHAR;
      old_field RECORD;
    BEGIN
      /* load trigger config */
      SELECT *
        INTO trigger_row
        FROM #{prefix}.triggers
        WHERE table_prefix = TG_TABLE_SCHEMA AND table_name = TG_TABLE_NAME;

      IF
        (trigger_row.mode = 'ignore' AND (trigger_row.override_transaction_id IS NULL OR trigger_row.override_transaction_id != pg_current_xact_id())) OR
        (trigger_row.mode = 'capture' AND trigger_row.override_transaction_id = pg_current_xact_id())
      THEN
        RETURN NULL;
      END IF;

      /* instantiate change row */
      change_row = ROW(
        NEXTVAL('#{prefix}.changes_id_seq'),
        pg_current_xact_id(),
        LOWER(TG_OP::TEXT),
        TG_TABLE_SCHEMA::TEXT,
        TG_TABLE_NAME::TEXT,
        NULL,
        NULL,
        '{}'
      );

      /* build table_pk */
      IF trigger_row.primary_key_columns != '{}' THEN
        IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
          pk_source := NEW;
        ELSIF (TG_OP = 'DELETE') THEN
          pk_source := OLD;
        END IF;

        change_row.table_pk := '{}';

        FOREACH col_name IN ARRAY trigger_row.primary_key_columns LOOP
          EXECUTE 'SELECT $1.' || col_name || '::text' USING pk_source INTO pk_col_val;
          change_row.table_pk := change_row.table_pk || pk_col_val;
        END LOOP;
      END IF;

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

      /* filtered columns */
      FOREACH col_name IN ARRAY trigger_row.filtered_columns LOOP
        change_row.data = jsonb_set(change_row.data, ('{' || col_name || '}')::text[], jsonb('"[FILTERED]"'));
      END LOOP;

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
  end

  @spec create_triggers_table_index(prefix()) :: :ok
  @spec create_triggers_table_index(prefix(), atom()) :: :ok
  def create_triggers_table_index(prefix, override_transaction_id \\ :override_transaction_id) do
    create(
      index("triggers", [:table_prefix, :table_name],
        name: "table_index",
        unique: true,
        include: [
          :primary_key_columns,
          :excluded_columns,
          :filtered_columns,
          :mode,
          override_transaction_id
        ],
        prefix: prefix
      )
    )

    :ok
  end

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

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

    create_set_transaction_id_procedure(prefix)

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
          column: :id,
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

    execute("CREATE TYPE #{prefix}.trigger_mode AS ENUM('capture', 'ignore');")

    create table("triggers", primary_key: false, prefix: prefix) do
      add(:id, :bigserial, null: false, primary_key: true)
      add(:table_prefix, :string, null: false)
      add(:table_name, :string, null: false)
      add(:primary_key_columns, {:array, :string}, null: false)
      add(:excluded_columns, {:array, :string}, null: false)
      add(:filtered_columns, {:array, :string}, null: false)
      add(:mode, :"#{prefix}.trigger_mode", null: false)
      add(:override_transaction_id, :xid8, null: true)

      timestamps()
    end

    create_triggers_table_index(prefix)

    # ------------- Capture Function -------------

    create_capture_changes_procedure(prefix)

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()} | {:drop_schema, boolean()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) when is_list(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    execute("DROP FUNCTION #{prefix}.capture_changes;")

    drop(table("triggers", prefix: prefix))
    execute("DROP TYPE #{prefix}.trigger_mode;")

    drop(table("changes", prefix: prefix))
    execute("DROP TYPE #{prefix}.change_op;")

    drop(table("transactions", prefix: prefix))
    execute("DROP FUNCTION #{prefix}.set_transaction_id;")

    if Keyword.get(opts, :drop_schema, true) do
      execute("DROP SCHEMA #{prefix};")
    end

    :ok
  end
end
