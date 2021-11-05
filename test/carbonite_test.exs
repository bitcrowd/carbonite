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

    test "remembers the last processed position" do
      process(TestRepo, "rabbits", fn _tx, _memo ->
        :cont
      end)

      %Outbox{} = outbox = get_rabbits_outbox()
      assert outbox.last_transaction_id == 300_000
      assert outbox.memo == %{}
    end

    test "reduces the batch to the memo and remembers it" do
      process(TestRepo, "rabbits", fn tx, memo ->
        expected_id = Map.get(memo, "next_id", 100_000)

        assert tx.id == expected_id

        {:cont, memo: Map.put(memo, "next_id", expected_id + 100_000)}
      end)

      %Outbox{} = outbox = get_rabbits_outbox()
      assert outbox.last_transaction_id == 300_000
      assert outbox.memo == %{"next_id" => 400_000}
    end

    test "can be stopped and discards the last transaction" do
      process(TestRepo, "rabbits", fn _tx, _memo ->
        {:halt, memo: :ignored}
      end)

      %Outbox{} = outbox = get_rabbits_outbox()
      assert outbox.last_transaction_id == 0
      assert outbox.memo == %{}
    end

    test "can be stopped without discarding the last transaction" do
      process(TestRepo, "rabbits", fn _tx, _memo ->
        {:halt, discard: false, memo: %{"some" => "data"}}
      end)

      %Outbox{} = outbox = get_rabbits_outbox()
      assert outbox.last_transaction_id == 100_000
      assert outbox.memo == %{"some" => "data"}
    end

    test "starts at the last processed position (+1)" do
      update_rabbits_outbox(%{last_transaction_id: 200_000})

      process(TestRepo, "rabbits", fn tx, _memo ->
        send(self(), tx.id)
        :cont
      end)

      refute_received 100_000
      refute_received 200_000
      assert_received 300_000
    end

    test "passes down batch query options" do
      process(TestRepo, "rabbits", [min_age: 9_000], fn tx, _memo ->
        send(self(), tx.id)
        :cont
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

      process(TestRepo, "rabbits", [batch_filter: batch_filter], fn tx, _memo ->
        send(self(), tx.id)
        :cont
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
