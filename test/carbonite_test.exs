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

    test "passes the transactions and the memo to the process func" do
      process(TestRepo, "rabbits", fn tx, memo ->
        expected_id = Map.get(memo, "next_id", 100_000)

        assert tx.id == expected_id

        Map.put(memo, "next_id", expected_id + 100_000)
      end)
    end

    test "remembers the last processed position and the memo" do
      process(TestRepo, "rabbits", fn tx, memo ->
        sum = Map.get(memo, "sum", 0)
        Map.put(memo, "sum", sum + tx.id)
      end)

      %Outbox{} = outbox = get_rabbits_outbox()

      assert outbox.last_transaction_id == 300_000
      assert outbox.memo["sum"] == 600_000
    end

    test "starts at the last processed position (+1)" do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      process(TestRepo, "rabbits", fn tx, memo ->
        send(self(), tx.id)
        memo
      end)

      refute_received 100_000
      refute_received 200_000
      assert_received 300_000
    end

    test "passes down batch query options" do
      process(TestRepo, "rabbits", [min_age: 9_000], fn tx, memo ->
        send(self(), tx.id)
        memo
      end)

      assert_received 100_000
      refute_received 200_000
      refute_received 300_000
    end

    test "accepts a batch_filter function for refining the batch query" do
      batch_filter = fn query ->
        # mimicking the "min_age" behaviour in a custom filter
        max_inserted_at = DateTime.utc_now() |> DateTime.add(-9_000)
        where(query, [t], t.inserted_at < ^max_inserted_at)
      end

      process(TestRepo, "rabbits", [batch_filter: batch_filter], fn tx, memo ->
        send(self(), tx.id)
        memo
      end)

      assert_received 100_000
      refute_received 200_000
      refute_received 300_000
    end
  end

  describe "purge/2" do
    setup [:insert_past_transactions]

    setup do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      :ok
    end

    test "deletes transactions that have been processed by all outboxes" do
      purge(TestRepo)

      assert [%Transaction{id: 300_000}] = get_transactions()
    end

    test "passes down batch query options" do
      purge(TestRepo, min_age: 9_000)

      assert [%Transaction{id: 200_000}, %Transaction{id: 300_000}] = get_transactions()
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
