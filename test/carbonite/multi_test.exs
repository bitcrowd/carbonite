# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MultiTest do
  use Carbonite.APICase, async: true
  import Carbonite.Multi
  alias Carbonite.{Rabbit, TestRepo}

  describe "insert_transaction/3" do
    test "inserts a transaction within an Ecto.Multi" do
      assert {:ok, _} =
               Ecto.Multi.new()
               |> insert_transaction()
               |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
               |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
               |> TestRepo.transaction()
    end
  end

  describe "override_mode/2" do
    test "enables override mode for the current transaction" do
      assert {:ok, _} =
               Ecto.Multi.new()
               |> override_mode()
               |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
               |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
               |> TestRepo.transaction()
    end
  end
end
