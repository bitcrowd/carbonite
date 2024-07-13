# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarboniteAlternateTestSchema do
  use Ecto.Migration
  alias Carbonite.Migrations, as: M

  def up do
    M.up(M.patch_range(), carbonite_prefix: "alternate_test_schema")

    M.create_trigger(:rabbits, carbonite_prefix: "alternate_test_schema")

    M.put_trigger_config(:rabbits, :mode, :ignore, carbonite_prefix: "alternate_test_schema")

    M.create_outbox("alternate_outbox",
      carbonite_prefix: "alternate_test_schema"
    )
  end

  def down do
    M.drop_trigger(:rabbits, carbonite_prefix: "alternate_test_schema")

    M.down(Enum.reverse(M.patch_range()), carbonite_prefix: "alternate_test_schema")
  end
end
