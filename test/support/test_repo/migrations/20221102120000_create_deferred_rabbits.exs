# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.CreateDeferredRabbits do
  use Ecto.Migration

  def change do
    create table(:deferred_rabbits) do
      add(:name, :string)
      add(:age, :integer)
      add(:carrots, {:array, :string}, default: "{}")
    end

    Carbonite.Migrations.create_trigger(:deferred_rabbits, initially: :deferred)
  end

  def down do
    Carbonite.Migrations.drop_trigger(:deferred_rabbits)

    drop(table(:deferred_rabbits))
  end
end
