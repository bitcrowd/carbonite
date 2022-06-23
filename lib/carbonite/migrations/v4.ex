# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V4 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version
  alias Carbonite.Migrations.V1

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()}

  # This buffer ensures that the sequence is initialized to a value hopefully greater than the
  # current xact id, even if new `transactions` records have been inserted during the migration.
  @xact_id_buffer 5000

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
        (trigger_row.mode = 'ignore' AND (trigger_row.override_xact_id IS NULL OR trigger_row.override_xact_id != pg_current_xact_id())) OR
        (trigger_row.mode = 'capture' AND trigger_row.override_xact_id = pg_current_xact_id())
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
        '{}',
        NULL
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
          EXECUTE 'SELECT $1.' || col_name || '::TEXT' USING pk_source INTO pk_col_val;
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
        change_row.data = jsonb_set(change_row.data, ('{' || col_name || '}')::TEXT[], jsonb('"[FILTERED]"'));
      END LOOP;

      /* insert, fail gracefully unless transaction record present or NEXTVAL has never been called */
      BEGIN
        change_row.transaction_id = CURRVAL('#{prefix}.transactions_id_seq');

        /* verify that xact_id matches */
        IF NOT
          EXISTS(
            SELECT 1 FROM #{prefix}.transactions
            WHERE id = change_row.transaction_id AND xact_id = change_row.transaction_xact_id
          )
        THEN
          RAISE USING ERRCODE = 'foreign_key_violation';
        END IF;

        INSERT INTO #{prefix}.changes VALUES (change_row.*);
      EXCEPTION WHEN foreign_key_violation OR object_not_in_prerequisite_state THEN
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

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    lock_changes(prefix)

    # ------------- Change constraints -----------

    temporarily_drop_fk_on_changes(prefix, fn ->
      rename_id_column(prefix, "transactions", :id, :xact_id)
      rename_id_column(prefix, "changes", :transaction_id, :transaction_xact_id)

      squish_and_execute("ALTER TABLE #{prefix}.transactions DROP CONSTRAINT transactions_pkey;")

      squish_and_execute(
        "ALTER TABLE #{prefix}.transactions ADD PRIMARY KEY (id) INCLUDE (xact_id);"
      )
    end)

    temporarily_drop_default_on_outboxes(prefix, "0", fn ->
      change_type(prefix, "outboxes", "last_transaction_id", "BIGINT")
    end)

    # ------------- New ID sequence --------------

    %Postgrex.Result{rows: [[seq_start_with]]} =
      repo().query!("SELECT pg_current_xact_id()::TEXT::BIGINT + #{@xact_id_buffer};")

    """
    CREATE SEQUENCE #{prefix}.transactions_id_seq
    START WITH #{seq_start_with}
    OWNED BY #{prefix}.transactions.id;
    """
    |> squish_and_execute()

    """
    CREATE OR REPLACE FUNCTION #{prefix}.set_transaction_id() RETURNS TRIGGER AS
    $body$
    BEGIN
      BEGIN
        /* verify that no previous INSERT within current transaction (with same id) */
        IF
          EXISTS(
            SELECT 1 FROM #{prefix}.transactions
            WHERE id = COALESCE(NEW.id, CURRVAL('#{prefix}.transactions_id_seq'))
            AND xact_id = COALESCE(NEW.xact_id, pg_current_xact_id())
          )
        THEN
          NEW.id = COALESCE(NEW.id, CURRVAL('#{prefix}.transactions_id_seq'));
        END IF;
      EXCEPTION WHEN object_not_in_prerequisite_state THEN
        /* when NEXTVAL has never been called within session, we're good */
      END;

      NEW.id = COALESCE(NEW.id, NEXTVAL('#{prefix}.transactions_id_seq'));
      NEW.xact_id = COALESCE(NEW.xact_id, pg_current_xact_id());

      RETURN NEW;
    END
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()

    # ------------- override_xact_id -------------

    rename(table("triggers", prefix: prefix), :override_transaction_id, to: :override_xact_id)

    # ------------- Capture Function -------------

    create_capture_changes_procedure(prefix)

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    lock_changes(prefix)

    # ------------- Change constraints -----------

    temporarily_drop_fk_on_changes(prefix, fn ->
      squish_and_execute("ALTER TABLE #{prefix}.transactions DROP CONSTRAINT transactions_pkey;")
      squish_and_execute("ALTER TABLE #{prefix}.transactions ADD PRIMARY KEY (xact_id);")

      revert_id_column(prefix, "changes", :transaction_xact_id, :transaction_id)
      revert_id_column(prefix, "transactions", :xact_id, :id)
    end)

    temporarily_drop_default_on_outboxes(prefix, "0", fn ->
      change_type(prefix, "outboxes", "last_transaction_id", "BIGINT")
    end)

    # ------------- override_xact_id -------------

    rename(table("triggers", prefix: prefix), :override_xact_id, to: :override_transaction_id)

    # ------------ Restore functions -------------

    V1.create_set_transaction_id_procedure(prefix)
    V1.create_capture_changes_procedure(prefix)

    :ok
  end

  defp lock_changes(prefix) do
    squish_and_execute("LOCK TABLE #{prefix}.changes IN EXCLUSIVE MODE;")
  end

  defp rename_id_column(prefix, table, from, to) do
    rename(table(table, prefix: prefix), from, to: to)

    alter table(table, prefix: prefix) do
      add(from, :bigint, null: true)
    end

    squish_and_execute("UPDATE #{prefix}.#{table} SET #{from} = #{to}::TEXT::BIGINT;")

    alter table(table, prefix: prefix) do
      modify(from, :bigint, null: false)
    end
  end

  defp revert_id_column(prefix, table, from, to) do
    alter table(table, prefix: prefix) do
      remove(to)
    end

    rename(table(table, prefix: prefix), from, to: to)
  end

  defp change_type(prefix, table, column, type) do
    """
    ALTER TABLE #{prefix}.#{table}
    ALTER COLUMN #{column}
    SET DATA TYPE #{type}
    USING #{column}::text::#{type};
    """
    |> squish_and_execute()
  end

  defp temporarily_drop_fk_on_changes(prefix, callback) do
    """
    ALTER TABLE #{prefix}.changes
    DROP CONSTRAINT changes_transaction_id_fkey;
    """
    |> squish_and_execute()

    callback.()

    """
    ALTER TABLE #{prefix}.changes
    ADD CONSTRAINT changes_transaction_id_fkey
    FOREIGN KEY (transaction_id)
    REFERENCES #{prefix}.transactions
    ON DELETE CASCADE
    ON UPDATE CASCADE;
    """
    |> squish_and_execute()
  end

  defp temporarily_drop_default_on_outboxes(prefix, default, callback) do
    """
    ALTER TABLE #{prefix}.outboxes
    ALTER COLUMN last_transaction_id
    DROP DEFAULT;
    """
    |> squish_and_execute()

    callback.()

    """
    ALTER TABLE #{prefix}.outboxes
    ALTER COLUMN last_transaction_id
    SET DEFAULT #{default};
    """
    |> squish_and_execute()
  end
end
