# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V7 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()} | {:concurrently, boolean()}

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())
    concurrently = Keyword.get(opts, :concurrently, false)

    # Ecto.Migration.rename/2 does not yet support :prefix
    # https://github.com/elixir-ecto/ecto_sql/pull/573

    """
    ALTER INDEX #{prefix}.changes_transaction_id_index
    RENAME TO changes_transaction_xact_id_index;
    """
    |> squish_and_execute()

    create(index(:changes, [:transaction_id], prefix: prefix, concurrently: concurrently))

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    drop(index(:changes, [:transaction_id], prefix: prefix))

    """
    ALTER INDEX #{prefix}.changes_transaction_xact_id_index
    RENAME TO changes_transaction_id_index;
    """
    |> squish_and_execute()

    :ok
  end
end
