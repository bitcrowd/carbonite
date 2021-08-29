defmodule Carbonite.TestRepo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def change do
    Carbonite.Migrations.install()
    Carbonite.Migrations.install_trigger(:rabbits, excluded_columns: ["age"])
  end
end
