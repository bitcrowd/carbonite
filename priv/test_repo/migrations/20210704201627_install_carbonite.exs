# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1)
    Carbonite.Migrations.up(2)
    Carbonite.Migrations.create_trigger(:rabbits)
    Carbonite.Migrations.put_trigger_config(:rabbits, :excluded_columns, ["age"])
  end

  def down do
    Carbonite.Migrations.drop_trigger(:rabbits)
    Carbonite.Migrations.down(2)
    Carbonite.Migrations.down(1)
  end
end
