# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V3 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    create table("outboxes", primary_key: false, prefix: prefix) do
      add(:name, :string, null: false, primary_key: true)
      add(:memo, :map, null: false, default: "{}")
      add(:last_transaction_id, :xid8, null: false, default: "0::xid8")

      timestamps(type: :utc_datetime_usec)
    end

    alter table("transactions", prefix: prefix) do
      remove(:processed_at, :utc_datetime_usec)
    end

    :ok
  end

  @type down_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec down([down_option()]) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    alter table("transactions", prefix: prefix) do
      add(:processed_at, :utc_datetime_usec, null: true)
    end

    create(
      index("transactions", [:inserted_at],
        where: "processed_at IS NULL",
        prefix: prefix
      )
    )

    drop(table("outboxes", prefix: prefix))

    :ok
  end
end
