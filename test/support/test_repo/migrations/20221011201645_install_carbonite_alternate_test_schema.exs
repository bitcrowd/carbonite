# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarboniteAlternateTestSchema do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1..8, carbonite_prefix: "alternate_test_schema")

    Carbonite.Migrations.create_trigger(:rabbits, carbonite_prefix: "alternate_test_schema")

    Carbonite.Migrations.put_trigger_config(:rabbits, :mode, :ignore,
      carbonite_prefix: "alternate_test_schema"
    )

    Carbonite.Migrations.create_outbox("alternate_outbox",
      carbonite_prefix: "alternate_test_schema"
    )
  end

  def down do
    Carbonite.Migrations.drop_trigger(:rabbits, carbonite_prefix: "alternate_test_schema")

    Carbonite.Migrations.down(8..1, carbonite_prefix: "alternate_test_schema")
  end
end
