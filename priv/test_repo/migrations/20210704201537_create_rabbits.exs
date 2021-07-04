defmodule Carbonite.TestRepo.Migrations.CreateRabbits do
  use Ecto.Migration

  def change do
    create table(:rabbits) do
      add :name, :string
      add :age, :integer
    end
  end
end
