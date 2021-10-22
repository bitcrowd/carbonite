# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.MultiTest do
  use ExUnit.Case, async: true
  import Carbonite.Multi
  alias Carbonite.{Rabbit, TestRepo, Transaction}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(TestRepo)
  end

  describe "insert_transaction/3" do
    test "inserts a transaction within an Ecto.Multi" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> insert_transaction()
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> TestRepo.transaction()

      assert tx.meta == %{}
      assert_almost_now(tx.inserted_at)

      assert is_integer(tx.id)
      assert %Ecto.Association.NotLoaded{} = tx.changes
    end

    test "allows setting metadata" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> insert_transaction(%{meta: %{foo: 1}})
        |> TestRepo.transaction()

      # atoms deserialize to strings
      assert tx.meta == %{"foo" => 1}
    end

    test "merges metadata from process dictionary" do
      Carbonite.Transaction.put_meta(:foo, 1)

      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> insert_transaction()
        |> TestRepo.transaction()

      assert tx.meta == %{"foo" => 1}
    end

    test "subsequent inserts in a single transaction are ignored" do
      {:ok,
       %{
         carbonite_transaction1: %Carbonite.Transaction{} = tx1,
         carbonite_transaction2: %Carbonite.Transaction{} = tx2
       }} =
        Ecto.Multi.new()
        |> insert_transaction(%{meta: %{foo: 1}}, name: :carbonite_transaction1)
        |> insert_transaction(%{meta: %{foo: 2}}, name: :carbonite_transaction2)
        |> TestRepo.transaction()

      assert tx1.meta == %{"foo" => 1}
      assert tx2.meta == %{"foo" => 1}
    end
  end

  describe "override_mode/2" do
    test "enables override mode for the current transaction" do
      {:ok, _result} =
        Ecto.Multi.new()
        |> override_mode()
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> TestRepo.transaction()

      assert TestRepo.count(Transaction) == 0
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
