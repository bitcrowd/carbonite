# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarboniteAlternateTestSchema do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.up(2, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.up(3, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.up(4, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.up(5, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.up(6, carbonite_prefix: "alternate_test_schema")

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

    Carbonite.Migrations.down(6, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.down(5, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.down(4, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.down(3, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.down(2, carbonite_prefix: "alternate_test_schema")
    Carbonite.Migrations.down(1, carbonite_prefix: "alternate_test_schema")
  end
end
