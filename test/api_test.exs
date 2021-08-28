defmodule APITest do
  use ExUnit.Case, async: true
  alias Carbonite.{Rabbit, TestRepo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Carbonite.TestRepo)
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

    test "has `meta` option to set metadata" do
      {:ok, %{carbonite_transaction: %Carbonite.Transaction{} = tx}} =
        Ecto.Multi.new()
        |> Carbonite.insert("rabbit_inserted", meta: %{foo: 1})
        |> TestRepo.transaction()

      assert tx.type == "rabbit_inserted"
      assert tx.meta == %{foo: 1}

      # atoms deserialize to strings
      assert TestRepo.reload(tx).meta == %{"foo" => 1}
    end
  end

  defp assert_almost_now(datetime) do
    assert_in_delta DateTime.to_unix(datetime), DateTime.to_unix(DateTime.utc_now()), 1
  end
end
