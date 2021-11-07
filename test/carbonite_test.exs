# SPDX-License-Identifier: Apache-2.0

defmodule CarboniteTest do
  use Carbonite.APICase, async: true
  import Carbonite
  alias Carbonite.{Outbox, Rabbit, TestRepo, Transaction}

  describe "insert_transaction/3" do
    test "inserts a transaction" do
      assert {:ok, tx} = insert_transaction(TestRepo)

      assert tx.meta == %{}
      assert_almost_now(tx.inserted_at)

      assert is_integer(tx.id)
      assert %Ecto.Association.NotLoaded{} = tx.changes
    end

    test "allows setting metadata" do
      assert {:ok, tx} = insert_transaction(TestRepo, %{meta: %{foo: 1}})

      # atoms deserialize to strings
      assert tx.meta == %{"foo" => 1}
    end

    test "merges metadata from process dictionary" do
      Carbonite.Transaction.put_meta(:foo, 1)

      assert {:ok, tx} = insert_transaction(TestRepo)

      assert tx.meta == %{"foo" => 1}
    end

    test "subsequent inserts in a single transaction are ignored" do
      # Since we're running in the SQL sandbox, both of these transactions
      # actually reference the same transaction id.

      assert {:ok, tx1} = insert_transaction(TestRepo, %{meta: %{foo: 1}})
      assert {:ok, tx2} = insert_transaction(TestRepo, %{meta: %{foo: 2}})

      assert tx1.meta == %{"foo" => 1}
      assert tx2.meta == %{"foo" => 1}
    end
  end

  describe "override_mode/2" do
    test "enables override mode for the current transaction" do
      assert override_mode(TestRepo) == :ok

      %{name: "Jack", age: 99}
      |> Rabbit.create_changeset()
      |> TestRepo.insert!()

      assert get_transactions() == []
    end
  end

  describe "process/4" do
    setup [:insert_past_transactions]

    test "starts at the last processed position (+1)" do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      assert {:ok, _outbox} =
               process(TestRepo, "rabbits", fn [tx], _memo ->
                 send(self(), tx.id)
                 :cont
               end)

      refute_received 100_000
      refute_received 200_000
      assert_received 300_000
    end

    test "passes down batch query options" do
      assert {:ok, _outbox} =
               process(TestRepo, "rabbits", [min_age: 9_000], fn [tx], _memo ->
                 send(self(), tx.id)
                 :cont
               end)

      assert_received 100_000
      refute_received 200_000
      refute_received 300_000
    end

    test "remembers the last processed position" do
      assert {:ok, %Outbox{} = outbox} =
               process(TestRepo, "rabbits", fn _txs, _memo ->
                 :cont
               end)

      assert outbox.last_transaction_id == 300_000
    end

    test "remembers the returned memo" do
      update_rabbits_outbox(%{memo: %{"foo" => 1}})

      assert {:ok, %Outbox{} = outbox} =
               process(TestRepo, "rabbits", fn _txs, memo ->
                 {:cont, memo: Map.put(memo, "foo", memo["foo"] + 1)}
               end)

      assert outbox.memo == %{"foo" => 4}
    end

    test "when halted discards the last chunk" do
      update_rabbits_outbox(%{last_transaction_id: 200_000, memo: %{"foo" => 1}})

      assert {:halt, %Outbox{} = outbox} =
               process(TestRepo, "rabbits", fn _txs, _memo ->
                 :halt
               end)

      assert outbox.last_transaction_id == 200_000
      assert outbox.memo == %{"foo" => 1}
    end

    test "when halted still allows to update the outbox" do
      assert {:halt, %Outbox{} = outbox} =
               process(TestRepo, "rabbits", fn _txs, _memo ->
                 {:halt, last_transaction_id: 100_000, memo: %{"some" => "data"}}
               end)

      assert outbox.last_transaction_id == 100_000
      assert outbox.memo == %{"some" => "data"}
    end

    defp assert_chunks(opts, expected) do
      assert {:ok, %Outbox{} = outbox} =
               process(TestRepo, "rabbits", opts, fn txs, memo ->
                 chunks = Map.get(memo, "chunks", [])
                 {:cont, memo: Map.put(memo, "chunks", chunks ++ [ids(txs)])}
               end)

      assert outbox.memo == %{"chunks" => expected}
    end

    test "accepts a chunk option to send larger chunks to the process function" do
      assert_chunks([chunk: 2], [[100_000, 200_000], [300_000]])
    end

    test "defaults to chunk size 1" do
      assert_chunks([], [[100_000], [200_000], [300_000]])
    end

    test "continues querying until processable transactions are exhausted" do
      # Limit in place, but chunk is bigger than limit (so irrelevant).
      # Algorithm continues until query comes back empty.
      assert_chunks([chunk: 100, limit: 2], [[100_000, 200_000], [300_000]])
    end

    test "accepts a filter function for refining the batch query" do
      filter = fn query ->
        # mimicking the "min_age" behaviour in a custom filter
        max_inserted_at = DateTime.utc_now() |> DateTime.add(-9_000)
        where(query, [t], t.inserted_at < ^max_inserted_at)
      end

      assert {:ok, _outbox} =
               process(TestRepo, "rabbits", [chunk: 100, filter: filter], fn txs, _memo ->
                 assert ids(txs) == [100_000]
                 :cont
               end)
    end
  end

  describe "purge/2" do
    setup [:insert_past_transactions]

    setup do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      :ok
    end

    test "deletes transactions that have been processed by all outboxes" do
      assert {:ok, 2} = purge(TestRepo)

      assert [%Transaction{id: 300_000}] = get_transactions()
    end

    test "passes down batch query options" do
      assert {:ok, 1} = purge(TestRepo, min_age: 9_000)

      assert [%Transaction{id: 200_000}, %Transaction{id: 300_000}] = get_transactions()
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
