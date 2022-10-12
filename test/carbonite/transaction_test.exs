# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TransactionTest do
  use Carbonite.APICase, async: true
  alias Carbonite.{TestRepo, Transaction}
  alias Ecto.Adapters.SQL
  import Transaction

  describe "Schema" do
    test "uses the default carbonite_prefix" do
      {sql, _} = SQL.to_sql(:all, TestRepo, Transaction)
      assert String.contains?(sql, ~s("carbonite_default"."transactions"))
    end
  end

  describe "changeset/1" do
    test "transaction_changesets an Ecto.Changeset for a transaction" do
      %Ecto.Changeset{} = changeset = changeset()

      assert get_field(changeset, :meta) == %{}
    end

    test "allows setting metadata" do
      %Ecto.Changeset{} = changeset = changeset(%{meta: %{foo: 1}})

      assert get_field(changeset, :meta) == %{foo: 1}
    end

    test "merges metadata from process dictionary" do
      Carbonite.Transaction.put_meta(:foo, 1)
      Carbonite.Transaction.put_meta(:bar, 1)
      %Ecto.Changeset{} = changeset = changeset(%{meta: %{foo: 2}})

      assert get_field(changeset, :meta) == %{foo: 2, bar: 1}
    end
  end

  describe "Jason.Encoder implementation" do
    test "Transaction can be encoded to JSON" do
      json =
        %Carbonite.Transaction{
          id: 1,
          meta: %{"foo" => 1},
          inserted_at: ~U[2021-11-01T12:00:00Z],
          changes: [
            %Carbonite.Change{
              id: 1,
              op: :update,
              table_prefix: "default",
              table_name: "rabbits",
              table_pk: ["1"],
              data: %{"name" => "Jack"},
              changed: ["name"],
              changed_from: %{"name" => "Jane"}
            }
          ]
        }
        |> Jason.encode!()
        |> Jason.decode!()

      assert json ==
               %{
                 "changes" => [
                   %{
                     "changed" => ["name"],
                     "changed_from" => %{"name" => "Jane"},
                     "data" => %{"name" => "Jack"},
                     "id" => 1,
                     "op" => "update",
                     "table_name" => "rabbits",
                     "table_pk" => ["1"],
                     "table_prefix" => "default"
                   }
                 ],
                 "id" => 1,
                 "inserted_at" => "2021-11-01T12:00:00Z",
                 "meta" => %{"foo" => 1}
               }
    end
  end
end
