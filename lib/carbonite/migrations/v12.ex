# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V12 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version
  alias Carbonite.Migrations.V11

  @type prefix :: binary()

  defp create_capture_changes_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.capture_changes() RETURNS TRIGGER AS
    $body$
    DECLARE
      trigger_row RECORD;
      change_row #{prefix}.changes;

      pk_source RECORD;
      pk_col VARCHAR;
      pk_col_val VARCHAR;
    BEGIN
      /* load trigger config */
      WITH settings AS (SELECT NULLIF(current_setting('#{prefix}.override_mode', TRUE), '')::TEXT AS override_mode)
      SELECT
        primary_key_columns,
        excluded_columns,
        filtered_columns,
        CASE
          WHEN settings.override_mode = 'override' AND mode = 'ignore' THEN 'capture'
          WHEN settings.override_mode = 'override' AND mode = 'capture' THEN 'ignore'
          ELSE COALESCE(settings.override_mode, mode::text)
        END AS mode,
        store_changed_from
      INTO trigger_row
      FROM #{prefix}.triggers
      JOIN settings ON TRUE
      WHERE table_prefix = TG_TABLE_SCHEMA AND table_name = TG_TABLE_NAME;

      IF (trigger_row IS NULL) THEN
        RAISE '(carbonite) % on table %.% but no trigger record in #{prefix}.triggers',
          TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = 'no_data_found';
      END IF;

      /* skip if ignored */
      IF (trigger_row.mode = 'ignore') THEN
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
          pk_source := NEW;
        ELSIF (TG_OP = 'DELETE') THEN
          pk_source := OLD;
        END IF;

        change_row.table_pk = '{}';
        FOREACH pk_col IN ARRAY trigger_row.primary_key_columns LOOP
          EXECUTE 'SELECT $1.' || quote_ident(pk_col) || '::TEXT' USING pk_source INTO pk_col_val;
          change_row.table_pk := change_row.table_pk || pk_col_val;
        END LOOP;
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
          RAISE '(carbonite) % on table %.% without prior INSERT into #{prefix}.transactions',
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

  @type up_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    create_capture_changes_procedure(prefix)

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    V11.create_capture_changes_procedure(prefix)

    :ok
  end
end
