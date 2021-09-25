# SPDX-License-Identifier: Apache-2.0

defmodule QuertTest do
  use ExUnit.Case, async: true
  import Ecto.Query, only: [from: 2]
  alias Carbonite.{Change, Query, Rabbit, TestRepo, Transaction}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(TestRepo)
  end

  defp insert_transaction do
    {:ok, _} =
      Ecto.Multi.new()
      |> Carbonite.insert()
      |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
      |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
      |> TestRepo.transaction()
  end

  defp count(schema) do
    schema
    |> from(select: count())
    |> TestRepo.one!(prefix: Carbonite.default_prefix())
  end

  describe "current_transaction/2" do
    setup do
      insert_transaction()
      :ok
    end

    test "can fetch the current transaction when inside SQL sandbox" do
      assert [%Transaction{}] = TestRepo.all(Query.current_transaction())
    end

    test "can preload changes alongside the transaction" do
      assert [%Transaction{changes: [%Change{}]}] =
               TestRepo.all(Query.current_transaction(preload: :changes))

      assert [%Transaction{changes: [%Change{}]}] =
               TestRepo.all(Query.current_transaction(preload: true))
    end

    test "can be used to erase the current transaction" do
      assert count(Transaction) == 1
      assert count(Change) == 1

      TestRepo.delete_all(Query.current_transaction())

      assert count(Transaction) == 0
      assert count(Change) == 0

      # No unique constraint error as transaction has been deleted.
      insert_transaction()
    end
  end
end
