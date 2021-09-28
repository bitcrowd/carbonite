# SPDX-License-Identifier: Apache-2.0

defmodule CaptureTest do
  use ExUnit.Case, async: true
  import Ecto.Adapters.SQL, only: [query!: 2]
  alias Carbonite.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(TestRepo)
  end

  defp query!(statement), do: query!(TestRepo, statement)

  defp insert_transaction do
    query!("INSERT INTO carbonite_default.transactions (inserted_at) VALUES (NOW());")
  end

  defp insert_jack do
    query!("INSERT INTO rabbits (name, age) VALUES ('Jack', 99);")
  end

  defp select_changes do
    "SELECT * FROM carbonite_default.changes;"
    |> query!()
    |> postgrex_result_to_structs()
  end

  defp select_rabbits do
    "SELECT * FROM public.rabbits ORDER BY id DESC;"
    |> query!()
    |> postgrex_result_to_structs()
  end

  defp last_rabbit_id do
    select_rabbits()
    |> List.last()
    |> Map.fetch!("id")
    |> to_string()
  end

  defp postgrex_result_to_structs(%Postgrex.Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  describe "change capture trigger" do
    test "INSERTs on tables are tracked as changes" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
      end)

      assert [
               %{
                 "id" => _,
                 "transaction_id" => _,
                 "table_prefix" => "public",
                 "table_name" => "rabbits",
                 "op" => "insert",
                 "changed" => [],
                 "data" => %{"id" => _, "name" => "Jack"}
               }
             ] = select_changes()
    end

    test "UPDATEs on tables are tracked as changes" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET name = 'Jane' WHERE name = 'Jack';")
      end)

      assert [
               %{
                 "op" => "insert",
                 "changed" => [],
                 "data" => %{"id" => _, "name" => "Jack"}
               },
               %{
                 "op" => "update",
                 "changed" => ["name"],
                 "data" => %{"id" => _, "name" => "Jane"}
               }
             ] = select_changes()
    end

    test "DELETEs on tables are tracked as changes" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("DELETE FROM rabbits WHERE name = 'Jack';")
      end)

      assert [
               %{
                 "op" => "insert",
                 "changed" => [],
                 "data" => %{"id" => _, "name" => "Jack"}
               },
               %{
                 "op" => "delete",
                 "changed" => [],
                 "data" => %{"id" => _, "name" => "Jack"}
               }
             ] = select_changes()
    end

    test "table primary key is written for INSERTs" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
      end)

      rabbit_id = last_rabbit_id()

      assert [%{"table_pk" => [^rabbit_id]}] = select_changes()
    end

    test "table primary key is written for UPDATEs" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET name = 'Jane' WHERE name = 'Jack';")
      end)

      rabbit_id = last_rabbit_id()

      assert [
               %{"table_pk" => [^rabbit_id]},
               %{"table_pk" => [^rabbit_id]}
             ] = select_changes()
    end

    test "table primary key is written for DELETEs" do
      {:ok, rabbit_id} =
        TestRepo.transaction(fn ->
          insert_transaction()
          insert_jack()
          rabbit_id = last_rabbit_id()
          query!("DELETE FROM rabbits WHERE name = 'Jack';")
          rabbit_id
        end)

      assert [
               %{"table_pk" => [^rabbit_id]},
               %{"table_pk" => [^rabbit_id]}
             ] = select_changes()
    end

    test "table_pk is NULL when primary_key_columns is empty" do
      query!("UPDATE carbonite_default.triggers SET primary_key_columns = '{}';")

      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
      end)

      assert [%{"table_pk" => nil}] = select_changes()
    end

    test "override mode reverses the default mode" do
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET override_transaction_id = pg_current_xact_id();
        """)

        insert_jack()
      end)

      assert select_changes() == []
    end

    test "a friendly error is raised when transaction is not inserted or is inserted too late" do
      msg =
        "ERROR 23503 (foreign_key_violation) INSERT on table public.rabbits " <>
          "without prior INSERT into carbonite_default.transactions"

      assert_raise Postgrex.Error, msg, fn ->
        TestRepo.transaction(&insert_jack/0)
      end
    end

    test "a (not quite as) friendly error is raised when transaction is inserted twice" do
      TestRepo.transaction(fn ->
        insert_transaction()

        assert_raise Postgrex.Error,
                     ~r/duplicate key value violates unique constraint "transactions_pkey"/,
                     fn ->
                       insert_transaction()
                     end
      end)
    end
  end

  describe "excluded columns" do
    test "excluded columns do not appear in captured data" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
      end)

      assert [%{"data" => data}] = select_changes()
      refute Map.has_key?(data, "age")
    end

    test "UPDATEs on only excluded fields are not tracked" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET age = 100 WHERE name = 'Jack';")
      end)

      assert [%{"age" => 100}] = select_rabbits()
      assert [%{"op" => "insert"}] = select_changes()
    end
  end
end
