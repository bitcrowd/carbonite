# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Rabbit do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, change: 2]

  schema "rabbits" do
    field(:name, :string)
    field(:age, :integer)
  end

  def create_changeset(params) do
    cast(%__MODULE__{}, params, [:name, :age])
  end

  def rename_changeset(%__MODULE__{} = rabbit, new_name) do
    change(rabbit, %{name: new_name})
  end

  def age_changeset(%__MODULE__{} = rabbit) do
    change(rabbit, %{age: rabbit.age + 1})
  end

  # Dirty little helper to make rabbits on the console.
  def make do
    Ecto.Multi.new()
    |> Carbonite.insert()
    |> Ecto.Multi.insert(:rabbit, fn _ -> create_changeset(%{age: 101, name: "Janet"}) end)
    |> Carbonite.TestRepo.transaction()
  end
end
