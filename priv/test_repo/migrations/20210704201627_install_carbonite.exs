defmodule Carbonite.TestRepo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def change do
    Carbonite.Migrations.up()
    Carbonite.Migrations.install_on_table(:rabbits, except: [:age])
  end
end
