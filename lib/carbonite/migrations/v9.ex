# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V9 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version
  alias Carbonite.Migrations.V4

  @type prefix :: binary()

  @spec create_set_transaction_id_procedure(prefix()) :: :ok
  def create_set_transaction_id_procedure(prefix) do
    """
    CREATE OR REPLACE FUNCTION #{prefix}.set_transaction_id() RETURNS TRIGGER AS
    $body$
    BEGIN
      BEGIN
        /* verify that no previous INSERT within current transaction (with same id) */
        IF
          EXISTS(
            WITH constants AS (
              SELECT
                COALESCE(NEW.id, CURRVAL('#{prefix}.transactions_id_seq')) AS id,
                COALESCE(NEW.xact_id, pg_current_xact_id()) AS xact_id
            )
            SELECT 1 FROM #{prefix}.transactions
            JOIN constants
            ON constants.id = transactions.id
            AND constants.xact_id = transactions.xact_id
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

    :ok
  end

  @type up_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    create_set_transaction_id_procedure(prefix)

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    V4.create_set_transaction_id_procedure(prefix)

    :ok
  end
end
