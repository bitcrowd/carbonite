# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.QueryTest do
  use ExUnit.Case, async: true
  alias Carbonite.{Change, Query, Rabbit, TestRepo, Transaction}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(TestRepo)
  end

  defp insert_rabbits(_) do
    {:ok, results} =
      Ecto.Multi.new()
      |> Carbonite.Multi.insert_transaction()
      |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
      |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
      |> Ecto.Multi.put(:params2, %{name: "Lily", age: 172})
      |> Ecto.Multi.insert(:rabbit2, &Rabbit.create_changeset(&1.params2))
      |> TestRepo.transaction()

    Map.take(results, [:rabbit, :rabbit2])
  end

  @historic_transaction_ids [100_000_000, 200_000_000]

  defp insert_historic_transactions(_) do
    for id <- @historic_transaction_ids do
      TestRepo.insert!(%Transaction{id: id}, prefix: Carbonite.default_prefix())
    end

    :ok
  end

  describe "transactions/2" do
    setup [:insert_historic_transactions, :insert_rabbits]

    test "fetches all transactions" do
      assert length(TestRepo.all(Query.transactions())) == 3
    end

    test "can preload changes alongside the transaction" do
      assert [%Transaction{changes: []} | _] = TestRepo.all(Query.transactions(preload: :changes))

      assert [%Transaction{changes: []} | _] =
               TestRepo.all(Query.transactions(preload: [:changes]))

      assert [%Transaction{changes: []} | _] = TestRepo.all(Query.transactions(preload: true))
    end
  end

  describe "current_transaction/2" do
    setup [:insert_historic_transactions, :insert_rabbits]

    test "can fetch the current transaction when inside SQL sandbox" do
      assert %Transaction{id: id} = TestRepo.one!(Query.current_transaction())

      assert id not in @historic_transaction_ids
    end

    test "can preload changes alongside the transaction" do
      assert %Transaction{changes: [%Change{}, %Change{}]} =
               TestRepo.one!(Query.current_transaction(preload: :changes))

      assert %Transaction{changes: [%Change{}, %Change{}]} =
               TestRepo.one!(Query.current_transaction(preload: [:changes]))

      assert %Transaction{changes: [%Change{}, %Change{}]} =
               TestRepo.one!(Query.current_transaction(preload: true))
    end

    test "can be used to erase the current transaction" do
      assert TestRepo.count(Transaction) == 3
      assert TestRepo.count(Change) == 2

      TestRepo.delete_all(Query.current_transaction())

      assert TestRepo.count(Transaction) == 2
      assert TestRepo.count(Change) == 0
    end
  end

  describe "changes/2" do
    setup [:insert_rabbits]

    defp changes(rabbit, opts \\ []) do
      rabbit
      |> Query.changes(opts)
      |> TestRepo.all()
    end

    test "queries changes for a given record given its struct", %{rabbit: rabbit} do
      assert [%Change{data: %{"name" => "Jack"}}] = changes(rabbit)
    end

    test "can preload the transaction", %{rabbit: rabbit} do
      assert [%Change{transaction: %Transaction{}}] = changes(rabbit, preload: :transaction)
      assert [%Change{transaction: %Transaction{}}] = changes(rabbit, preload: [:transaction])
      assert [%Change{transaction: %Transaction{}}] = changes(rabbit, preload: true)
    end

    test "can override the schema prefix", %{rabbit: rabbit} do
      assert changes(rabbit, table_prefix: "foo") == []
      assert [%Change{}] = changes(rabbit, table_prefix: "public")
    end
  end
end
