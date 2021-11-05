# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.QueryTest do
  use Carbonite.APICase, async: true
  alias Carbonite.{Change, Outbox, Query, Rabbit, TestRepo, Transaction}

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

  describe "transactions/2" do
    setup [:insert_past_transactions, :insert_rabbits]

    test "fetches all transactions" do
      assert length(TestRepo.all(Query.transactions())) == 4
    end

    test "can preload changes alongside the transaction" do
      assert [%Transaction{changes: []} | _] = TestRepo.all(Query.transactions(preload: :changes))

      assert [%Transaction{changes: []} | _] =
               TestRepo.all(Query.transactions(preload: [:changes]))

      assert [%Transaction{changes: []} | _] = TestRepo.all(Query.transactions(preload: true))
    end

    test "accepts an atom as prefix" do
      assert length(TestRepo.all(Query.transactions(carbonite_prefix: :carbonite_default))) == 4
    end
  end

  describe "current_transaction/2" do
    setup [:insert_past_transactions, :insert_rabbits]

    test "can fetch the current transaction when inside SQL sandbox", %{
      transactions: transactions
    } do
      assert %Transaction{id: id} = TestRepo.one!(Query.current_transaction())

      assert id not in ids(transactions)
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
      assert TestRepo.count(Transaction) == 4
      assert TestRepo.count(Change) == 2

      TestRepo.delete_all(Query.current_transaction())

      assert TestRepo.count(Transaction) == 3
      assert TestRepo.count(Change) == 0
    end
  end

  describe "outbox/1" do
    defp outbox(name) do
      name
      |> Query.outbox()
      |> TestRepo.one()
    end

    test "gets an outbox by name" do
      assert %Outbox{} = outbox("rabbits")
      refute outbox("doesnotexist")
    end
  end

  describe "outbox_queue/2" do
    setup [:insert_past_transactions]

    defp outbox_queue(opts \\ []) do
      outbox = get_rabbits_outbox()

      outbox
      |> Query.outbox_queue(opts)
      |> TestRepo.all()
    end

    test "filters by id > last_transaction_id" do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      assert ids(outbox_queue()) == [300_000]
    end

    test "orders results by id" do
      assert ids(outbox_queue()) == [100_000, 200_000, 300_000]
    end

    test "can limit the batch_size" do
      assert ids(outbox_queue(batch_size: 1)) == [100_000]
    end

    test "can filter by min_age" do
      assert ids(outbox_queue(min_age: 9_000)) == [100_000]
    end

    test "preloads changes by default" do
      assert [%Transaction{changes: []} | _] = outbox_queue()
    end

    test "can not preload changes" do
      assert [%Transaction{changes: %Ecto.Association.NotLoaded{}} | _] =
               outbox_queue(preload: false)
    end
  end

  describe "outbox_done/1" do
    setup [:insert_past_transactions]

    defp outbox_done(opts \\ []) do
      opts
      |> Query.outbox_done()
      |> TestRepo.all()
    end

    test "filters by id >= MIN(outboxes.last_transaction_id)" do
      assert ids(outbox_done()) == []

      update_rabbits_outbox(%{last_transaction_id: 200_000})

      assert ids(outbox_done()) == [100_000, 200_000]

      TestRepo.insert!(
        %Outbox{name: "second", last_transaction_id: 100_000},
        prefix: :carbonite_default
      )

      assert ids(outbox_done()) == [100_000]

      TestRepo.delete_all(Outbox, prefix: :carbonite_default)

      assert ids(outbox_done()) == [100_000, 200_000, 300_000]
    end

    test "can filter by min_age" do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      assert ids(outbox_done(min_age: 9_000)) == [100_000]
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
