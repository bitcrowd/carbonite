# SPDX-License-Identifier: Apache-2.0

defmodule APITest do
  use ExUnit.Case, async: true
  alias Carbonite.{Rabbit, TestRepo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Carbonite.TestRepo)
  end

  describe "build/2" do
    test "builds an Ecto.Changeset for a transaction" do
      %Ecto.Changeset{} = changeset = Carbonite.build()

      assert changeset.changes.meta == %{}
    end

    test "allows setting metadata" do
      %Ecto.Changeset{} = changeset = Carbonite.build(meta: %{foo: 1})

      assert changeset.changes.meta == %{foo: 1}
    end

    test "merges metadata from process dictionary" do
      Carbonite.put_meta(:foo, 1)
      Carbonite.put_meta(:bar, 1)
      %Ecto.Changeset{} = changeset = Carbonite.build(meta: %{foo: 2})

      assert changeset.changes.meta == %{foo: 2, bar: 1}
    end
  end

  describe "insert/3" do
    test "inserts a transaction within an Ecto.Multi" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert()
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
        |> Carbonite.insert(meta: %{foo: 1})
        |> TestRepo.transaction()

      assert tx.meta == %{foo: 1}

      # atoms deserialize to strings
      assert TestRepo.reload(tx).meta == %{"foo" => 1}
    end

    test "merges metadata from process dictionary" do
      Carbonite.put_meta(:foo, 1)

      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert()
        |> TestRepo.transaction()

      assert tx.meta == %{foo: 1}
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
