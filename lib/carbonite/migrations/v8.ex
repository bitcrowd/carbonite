# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V8 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version
  alias Carbonite.Migrations.V6

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()}

  defp create_record_dynamic_varchar_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.record_dynamic_varchar(source RECORD, col VARCHAR)
    RETURNS VARCHAR AS
    $body$
    DECLARE
      result VARCHAR;
    BEGIN
      EXECUTE 'SELECT $1.' || quote_ident(col) || '::TEXT' USING source INTO result;

      RETURN result;
    END;
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()
  end

  defp create_record_dynamic_varchar_agg(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.record_dynamic_varchar_agg(source RECORD, cols VARCHAR[])
    RETURNS VARCHAR[] AS
    $body$
    DECLARE
      col VARCHAR;
      result VARCHAR[];
    BEGIN
      result := '{}';

      FOREACH col IN ARRAY cols LOOP
        result := result || (SELECT #{prefix}.record_dynamic_varchar(source, col));
      END LOOP;

      RETURN result;
    END;
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()
  end

  defp create_jsonb_redact_keys_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.jsonb_redact_keys(source JSONB, keys VARCHAR[]) RETURNS JSONB AS
    $body$
    DECLARE
      keys_intersect VARCHAR[];
      key VARCHAR;
    BEGIN
      SELECT ARRAY(
        SELECT UNNEST(ARRAY(SELECT jsonb_object_keys(source)))
        INTERSECT
        SELECT UNNEST(keys)
      ) INTO keys_intersect;

      FOREACH key IN ARRAY keys_intersect LOOP
        source := jsonb_set(source, ('{' || key || '}')::TEXT[], jsonb('"[FILTERED]"'));
      END LOOP;

      RETURN source;
    END;
    $body$
    LANGUAGE plpgsql;
    """
    |> squish_and_execute()
  end

  defp create_capture_changes_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      trigger_row #{prefix}.triggers;
      change_row #{prefix}.changes;
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
      change_row := ROW(
        NEXTVAL('#{prefix}.changes_id_seq'),
        pg_current_xact_id(),
        LOWER(TG_OP::TEXT),
        TG_TABLE_SCHEMA::TEXT,
        TG_TABLE_NAME::TEXT,
        NULL,
        NULL,
        '{}',
        NULL,
        NULL
      );

      /* collect table pk */
      IF trigger_row.primary_key_columns != '{}' THEN
        IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
          SELECT #{prefix}.record_dynamic_varchar_agg(NEW, trigger_row.primary_key_columns)
          INTO change_row.table_pk;
        ELSIF (TG_OP = 'DELETE') THEN
          SELECT #{prefix}.record_dynamic_varchar_agg(OLD, trigger_row.primary_key_columns)
          INTO change_row.table_pk;
        END IF;
      END IF;

      /* collect version data */
      IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
        SELECT to_jsonb(NEW.*) - trigger_row.excluded_columns
        INTO change_row.data;
      ELSIF (TG_OP = 'DELETE') THEN
        SELECT to_jsonb(OLD.*) - trigger_row.excluded_columns
        INTO change_row.data;
      END IF;

      /* change tracking for UPDATEs */
      IF (TG_OP = 'UPDATE') THEN
        change_row.changed_from = '{}'::JSONB;

        SELECT jsonb_object_agg(before.key, before.value)
        FROM jsonb_each(to_jsonb(OLD.*) - trigger_row.excluded_columns) AS before
        WHERE (change_row.data->before.key)::JSONB != before.value
        INTO change_row.changed_from;

        SELECT ARRAY(SELECT jsonb_object_keys(change_row.changed_from))
        INTO change_row.changed;

        /* skip persisting this update if nothing has changed */
        IF change_row.changed = '{}' THEN
          RETURN NULL;
        END IF;

        /* persisting the old data is opt-in, discard if not configured. */
        IF trigger_row.store_changed_from IS FALSE THEN
          change_row.changed_from := NULL;
        END IF;
      END IF;

      /* filtered columns */
      SELECT #{prefix}.jsonb_redact_keys(change_row.data, trigger_row.filtered_columns)
      INTO change_row.data;

      IF change_row.changed_from IS NOT NULL THEN
        SELECT #{prefix}.jsonb_redact_keys(change_row.changed_from, trigger_row.filtered_columns)
        INTO change_row.changed_from;
      END IF;

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

    create_record_dynamic_varchar_procedure(prefix)
    create_record_dynamic_varchar_agg(prefix)
    create_jsonb_redact_keys_procedure(prefix)
    create_capture_changes_procedure(prefix)

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    V6.create_capture_changes_procedure(prefix)
    execute("DROP FUNCTION #{prefix}.jsonb_redact_keys;")
    execute("DROP FUNCTION #{prefix}.record_dynamic_varchar_agg;")
    execute("DROP FUNCTION #{prefix}.record_dynamic_varchar;")

    :ok
  end
end
