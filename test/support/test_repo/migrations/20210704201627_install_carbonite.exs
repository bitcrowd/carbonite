# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.InstallCarbonite do
  use Ecto.Migration
  alias Carbonite.Migrations, as: M

  def up do
    M.up(M.patch_range())
    M.create_trigger(:rabbits)
    M.put_trigger_config(:rabbits, :excluded_columns, ["age"])
    M.put_trigger_config(:rabbits, :store_changed_from, true)
    M.create_outbox("rabbits")
  end

  def down do
    M.drop_trigger(:rabbits)
    M.down(Enum.reverse(M.patch_range()))
  end
end
