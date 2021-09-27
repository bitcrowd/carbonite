# SPDX-License-Identifier: Apache-2.0

defmodule QuertTest do
  use ExUnit.Case, async: true
  import Ecto.Query, only: [from: 2]
  alias Carbonite.{Change, Query, Rabbit, TestRepo, Transaction}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(TestRepo)
  end

  defp insert_rabbits(_ \\ nil) do
    {:ok, results} =
      Ecto.Multi.new()
      |> Carbonite.insert()
      |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
      |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
      |> Ecto.Multi.put(:params2, %{name: "Lily", age: 172})
      |> Ecto.Multi.insert(:rabbit2, &Rabbit.create_changeset(&1.params2))
      |> TestRepo.transaction()

    Map.take(results, [:rabbit, :rabbit2])
  end

  defp count(schema) do
    schema
    |> from(select: count())
    |> TestRepo.one!(prefix: Carbonite.default_prefix())
  end

  describe "current_transaction/2" do
    setup [:insert_rabbits]

    test "can fetch the current transaction when inside SQL sandbox" do
      assert [%Transaction{}] = TestRepo.all(Query.current_transaction())
    end

    test "can preload changes alongside the transaction" do
      assert [%Transaction{changes: [%Change{}, %Change{}]}] =
               TestRepo.all(Query.current_transaction(preload: :changes))

      assert [%Transaction{changes: [%Change{}, %Change{}]}] =
               TestRepo.all(Query.current_transaction(preload: [:changes]))

      assert [%Transaction{changes: [%Change{}, %Change{}]}] =
               TestRepo.all(Query.current_transaction(preload: true))
    end

    test "can be used to erase the current transaction" do
      assert count(Transaction) == 1
      assert count(Change) == 2

      TestRepo.delete_all(Query.current_transaction())

      assert count(Transaction) == 0
      assert count(Change) == 0

      # No unique constraint error as transaction has been deleted.
      insert_rabbits()
    end
  end

  describe "changes/2" do
    setup [:insert_rabbits]

    test "queries changes for a given record given its struct", %{rabbit: rabbit} do
      assert [%Change{new: %{"name" => "Jack"}}] = Query.changes(rabbit) |> TestRepo.all()
    end

    test "can preload the transaction", %{rabbit: rabbit} do
      assert [%Change{transaction: %Transaction{}}] =
               Query.changes(rabbit, preload: :transaction) |> TestRepo.all()

      assert [%Change{transaction: %Transaction{}}] =
               Query.changes(rabbit, preload: [:transaction]) |> TestRepo.all()

      assert [%Change{transaction: %Transaction{}}] =
               Query.changes(rabbit, preload: true) |> TestRepo.all()
    end
  end
end
