# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo.Migrations.CreateWeirdCharacterRabbits do
  use Ecto.Migration
  alias Carbonite.Migrations, as: M

  def change do
    execute(~s|CREATE SCHEMA "default";|, ~s|DROP SCHEMA "default";|)

    create table("rabbits;", prefix: "default") do
      add(:name, :string)
      add(:age, :integer)
      add(:carrots, {:array, :string}, default: "{}")
    end

    M.create_trigger("rabbits;", table_prefix: "default")
  end
end
