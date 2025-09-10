# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MultiTest do
  use Carbonite.APICase, async: true
  import Carbonite.Multi
  alias Carbonite.{Query, Rabbit, TestRepo}

  describe "insert_transaction/3" do
    test "inserts a transaction within an Ecto.Multi" do
      assert {:ok, _} =
               Ecto.Multi.new()
               |> insert_transaction()
               |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
               |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
               |> TestRepo.transaction()
    end

    test "operation names include the given prefix option" do
      assert %Ecto.Multi{operations: [{:carbonite_transaction, _}]} =
               insert_transaction(Ecto.Multi.new())

      assert %Ecto.Multi{operations: [{{:carbonite_transaction, "custom"}, _}]} =
               insert_transaction(Ecto.Multi.new(), %{}, carbonite_prefix: "custom")
    end
  end

  describe "delete_transaction_if_empty/2" do
    test "deletes current transaction if empty within an Ecto.Multi" do
      assert {:ok, _} =
               Ecto.Multi.new()
               |> insert_transaction()
               |> delete_transaction_if_empty()
               |> TestRepo.transaction()

      refute TestRepo.exists?(Query.current_transaction())
    end

    test "operation names include the given prefix option" do
      assert %Ecto.Multi{operations: [{:delete_carbonite_transaction, _}]} =
               delete_transaction_if_empty(Ecto.Multi.new())

      assert %Ecto.Multi{operations: [{{:delete_carbonite_transaction, "custom"}, _}]} =
               delete_transaction_if_empty(Ecto.Multi.new(), carbonite_prefix: "custom")
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
