defmodule Carbonite.Migrations.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(prefix) do
    if prefix != "public" do
      execute("CREATE SCHEMA IF NOT EXISTS #{prefix}")
    end

    execute("CREATE EXTENSION IF NOT EXISTS hstore;")

    execute("CREATE TYPE carbonite_change_op AS ENUM('insert', 'update', 'delete');")

    create table("carbonite_transactions", primary_key: false, prefix: prefix) do
      add(:id, :xid8, null: false, primary_key: true)
      add(:type, :string, null: false)
      add(:meta, :map, null: false, default: %{})

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    execute("""
    CREATE FUNCTION #{prefix}.carbonite_set_transaction_id() RETURNS TRIGGER AS
    $body$
    BEGIN
      NEW.id = pg_current_xact_id();
      RETURN NEW;
    END
    $body$
    LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER carbonite_transaction_trg
    BEFORE INSERT
    ON #{prefix}.carbonite_transactions
    FOR EACH ROW
    EXECUTE PROCEDURE #{prefix}.carbonite_set_transaction_id();
    """)

    create table("carbonite_changes", prefix: prefix, primary_key: false) do
      add(:id, :bigserial, null: false, primary_key: true)

      add(
        :transaction_id,
        references(:carbonite_transactions,
          on_delete: :delete_all,
          on_update: :update_all,
          type: :xid8,
          prefix: prefix
        ),
        null: false
      )

      add(:op, :carbonite_change_op, null: false)
      add(:table_name, :string, null: false)
      add(:relid, :oid, null: false)
      add(:row_data, :hstore, null: false)
      add(:changes, :hstore)
    end

    create(index("carbonite_changes", [:transaction_id], prefix: prefix))

    execute("""
    CREATE FUNCTION #{prefix}.carbonite_capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      change_row #{prefix}.carbonite_changes;
      excluded_cols text[] = ARRAY[]::text[];
    BEGIN
      IF TG_ARGV[0] IS NOT NULL THEN
        excluded_cols = TG_ARGV[0]::text[];
      END IF;

      change_row = ROW(
        NEXTVAL('#{prefix}.carbonite_changes_id_seq'),
        pg_current_xact_id(),
        LOWER(TG_OP::TEXT),
        TG_TABLE_NAME::TEXT,
        TG_RELID,
        NULL,
        NULL
      );

      IF (TG_OP = 'UPDATE') THEN
        change_row.row_data = hstore(OLD.*) - excluded_cols;
        change_row.changes =  (hstore(NEW.*) - change_row.row_data) - excluded_cols;
        IF change_row.changes = hstore('') THEN
          -- All changed fields are ignored. Skip this update.
          RETURN NULL;
        END IF;
      ELSIF (TG_OP = 'DELETE') THEN
        change_row.row_data = hstore(OLD.*) - excluded_cols;
      ELSIF (TG_OP = 'INSERT') THEN
        change_row.row_data = hstore(NEW.*) - excluded_cols;
      END IF;

      BEGIN
        INSERT INTO #{prefix}.carbonite_changes VALUES (change_row.*);
      EXCEPTION WHEN foreign_key_violation THEN
        RAISE '% on table % without prior INSERT into carbonite_transactions',
          TG_OP, TG_TABLE_NAME USING ERRCODE = 'foreign_key_violation';
      END;

      RETURN NULL;
    END;
    $body$
    LANGUAGE plpgsql;
    """)

    :ok
  end

  def down(prefix) do
    execute("DROP FUNCTION #{prefix}.carbonite_capture_changes();")

    drop(table("carbonite_changes", prefix: prefix))

    execute("DROP TRIGGER carbonite_transaction_trg ON #{prefix}.carbonite_transactions;")
    execute("DROP FUNCTION #{prefix}.carbonite_set_transaction_id();")

    drop(table("carbonite_transactions", prefix: prefix))

    execute("DROP TYPE carbonite_change_op;")
  end
end
