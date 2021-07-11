defmodule CarboniteTest do
  use ExUnit.Case
  alias Carbonite.{Rabbit, TestRepo}

  setup do
    start_supervised!(Carbonite.TestRepo)
    :ok
  end

  describe "build/2" do
    test "builds an Ecto.Changeset for a transaction" do
      %Ecto.Changeset{} = changeset = Carbonite.build("rabbit_inserted")

      assert changeset.changes.type == "rabbit_inserted"
      assert changeset.changes.meta == %{}
    end

    test "allows setting metadata" do
      %Ecto.Changeset{} = changeset = Carbonite.build("rabbit_inserted", meta: %{foo: 1})

      assert changeset.changes.meta == %{foo: 1}
    end

    test "validates presence of type" do
      %Ecto.Changeset{} = changeset = Carbonite.build(nil)

      refute changeset.valid?
      assert {:type, {"can't be blank", [validation: :required]}} in changeset.errors
    end
  end

  describe "insert/3" do
    test "inserts a transaction within an Ecto.Multi" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted")
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> TestRepo.transaction()

      assert tx.type == "rabbit_inserted"
      assert tx.meta == %{}
      assert_almost_now(tx.inserted_at)

      assert is_integer(tx.id)
      assert %Ecto.Association.NotLoaded{} = tx.changes
    end

    test "transactions can have custom metadata" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted", meta: %{foo: 1})
        |> TestRepo.transaction()

      assert tx.type == "rabbit_inserted"
      assert tx.meta == %{foo: 1}

      # atoms deserialize to strings
      assert TestRepo.reload(tx).meta == %{"foo" => 1}
    end

    test "INSERTs on tables are tracked as changes" do
      {:ok,
       %{
         carbonite_transaction: %Carbonite.Transaction{id: tx_id} = tx,
         rabbit: %Carbonite.Rabbit{id: rabbit_id}
       }} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted")
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> TestRepo.transaction()

      assert [
               %Carbonite.Change{
                 changes: nil,
                 op: :insert,
                 row_data: row_data,
                 table_name: "rabbits",
                 transaction_id: ^tx_id
               }
             ] = TestRepo.preload(tx, :changes).changes

      # values are serialized to strings
      # 'age' field is excluded
      assert row_data == %{"id" => to_string(rabbit_id), "name" => "Jack"}
    end

    test "UPDATEs on tables are tracked as changes" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted")
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> Ecto.Multi.update(:renamed, &Rabbit.rename_changeset(&1.rabbit, "Jane"))
        |> TestRepo.transaction()

      # old data is in 'row_data', changes are in 'changes'
      assert [
               %Carbonite.Change{
                 changes: nil,
                 op: :insert,
                 row_data: %{"name" => "Jack"},
                 table_name: "rabbits"
               },
               %Carbonite.Change{
                 changes: %{"name" => "Jane"},
                 op: :update,
                 row_data: %{"name" => "Jack"},
                 table_name: "rabbits"
               }
             ] = TestRepo.preload(tx, :changes).changes
    end

    test "UPDATEs on only excluded fields are not tracked" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted")
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> Ecto.Multi.update(:aged, &Rabbit.age_changeset(&1.rabbit))
        |> TestRepo.transaction()

      assert [%Carbonite.Change{op: :insert}] = TestRepo.preload(tx, :changes).changes
    end

    test "DELETEs on tables are tracked as changes" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted")
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> Ecto.Multi.delete(:dead_rabbit, & &1.rabbit)
        |> TestRepo.transaction()

      # old data is in 'row_data', changes are in 'changes'
      assert [
               %Carbonite.Change{
                 changes: nil,
                 op: :insert,
                 row_data: %{"name" => "Jack"},
                 table_name: "rabbits"
               },
               %Carbonite.Change{
                 changes: nil,
                 op: :delete,
                 row_data: %{"name" => "Jack"},
                 table_name: "rabbits"
               }
             ] = TestRepo.preload(tx, :changes).changes
    end

    test "a friendly error is raised when transaction is not inserted or is inserted too late" do
      msg =
        "ERROR 23503 (foreign_key_violation) INSERT on table rabbits without prior INSERT into carbonite_transactions"

      assert_raise Postgrex.Error, msg, fn ->
        Ecto.Multi.new()
        |> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
        |> Ecto.Multi.insert(:rabbit, &Rabbit.create_changeset(&1.params))
        |> Carbonite.insert(:rabbit_inserted)
        |> TestRepo.transaction()
      end
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
