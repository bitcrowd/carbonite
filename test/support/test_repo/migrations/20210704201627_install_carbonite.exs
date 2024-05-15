# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1)
    Carbonite.Migrations.up(2)
    Carbonite.Migrations.up(3)
    Carbonite.Migrations.up(4)
    Carbonite.Migrations.up(5)
    Carbonite.Migrations.up(6)
    Carbonite.Migrations.up(7)
    Carbonite.Migrations.up(8)
    Carbonite.Migrations.create_trigger(:rabbits)
    Carbonite.Migrations.put_trigger_config(:rabbits, :excluded_columns, ["age"])
    Carbonite.Migrations.put_trigger_config(:rabbits, :store_changed_from, true)
    Carbonite.Migrations.create_outbox("rabbits")
  end

  def down do
    Carbonite.Migrations.drop_trigger(:rabbits)
    Carbonite.Migrations.down(8)
    Carbonite.Migrations.down(7)
    Carbonite.Migrations.down(6)
    Carbonite.Migrations.down(5)
    Carbonite.Migrations.down(4)
    Carbonite.Migrations.down(3)
    Carbonite.Migrations.down(2)
    Carbonite.Migrations.down(1)
  end
end
