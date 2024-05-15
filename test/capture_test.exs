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

  defp insert_jack(table \\ "rabbits") do
    query!("INSERT INTO #{table} (name, age) VALUES ('Jack', 99);")
  end

  defp upsert_jack(new_name, do_clause) do
    query!("""
    INSERT INTO rabbits (id, name) VALUES (#{last_rabbit_id()}, '#{new_name}')
    ON CONFLICT (id) DO #{do_clause}
    """)
  end

  defp select_changes do
    "SELECT * FROM carbonite_default.changes;"
    |> query!()
    |> postgrex_result_to_structs()
  end

  defp select_rabbits(table \\ "rabbits") do
    "SELECT * FROM #{table} ORDER BY id DESC;"
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

  defp transaction_with_simulated_commit(fun) do
    TestRepo.transaction(fn ->
      fun.()

      # We simulate the end of the transaction by setting the constraint to immediate now.
      # Otherwise when Ecto's SQL sandbox rolls back the transaction, our trigger never fires.
      query!("SET CONSTRAINTS ALL IMMEDIATE;")
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
                 "changed_from" => nil,
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
                 "changed_from" => nil,
                 "data" => %{"id" => _, "name" => "Jack"}
               },
               %{
                 "op" => "update",
                 "changed" => ["name"],
                 "changed_from" => %{"name" => "Jack"},
                 "data" => %{"id" => _, "name" => "Jane"}
               }
             ] = select_changes()
    end

    test "UPDATEs on tables are not tracked when data remains the same" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET name = 'Jack';")
      end)

      assert [%{"op" => "insert"}] = select_changes()
    end

    test "changes to arrays are detected correctly" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()

        # Additive array changes weren't detected correctly previously.
        query!("UPDATE rabbits SET carrots = '{carrot1}';")
      end)

      assert [
               _insert,
               %{"op" => "update", "changed_from" => %{"carrots" => []}, "changed" => ["carrots"]}
             ] = select_changes()
    end

    test "changed_from tracking is optional" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET name = 'Jane' WHERE name = 'Jack';")
        query!("UPDATE carbonite_default.triggers SET store_changed_from = FALSE;")
        query!("UPDATE rabbits SET name = 'Jiff' WHERE name = 'Jane';")
      end)

      assert [
               # INSERT has no changed_from
               %{"changed_from" => nil},
               # store_changed_from is true for rabbits (in migration)
               %{"changed_from" => %{"name" => "Jack"}},
               # demonstrating that it is optional
               %{"changed_from" => nil}
             ] = select_changes()
    end

    test "INSERT ON CONFLICT NOTHING is not tracked" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        upsert_jack("Jack", "NOTHING")
      end)

      assert [%{"op" => "insert"}] = select_changes()
    end

    test "INSERT ON CONFLICT SET ... is not tracked when data remains the same" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        upsert_jack("Jack", "UPDATE SET name = excluded.name;")
      end)

      assert [%{"op" => "insert"}] = select_changes()
    end

    test "INSERT ON CONFLICT SET ... is tracked when data is changed" do
      TestRepo.transaction(fn ->
        insert_transaction()
        insert_jack()
        upsert_jack("Jane", "UPDATE SET name = excluded.name;")
      end)

      assert [
               %{"op" => "insert"},
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
                 "changed_from" => nil,
                 "data" => %{"id" => _, "name" => "Jack"}
               },
               %{
                 "op" => "delete",
                 "changed" => [],
                 "changed_from" => nil,
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

    test "a friendly error is raised when transaction is not inserted or is inserted too late" do
      msg =
        "ERROR 23503 (foreign_key_violation) INSERT on table public.rabbits " <>
          "without prior INSERT into carbonite_default.transactions"

      # Case 1: Session has never called `NEXTVAL` -> `CURRVAL` fails.

      assert_raise Postgrex.Error, msg, fn ->
        TestRepo.transaction(&insert_jack/0)
      end

      # Case 2: Previous transaction (in session) has used `NEXTVAL` -> FK violation.

      query!("SELECT NEXTVAL('carbonite_default.transactions_id_seq');")

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

    test "initially deferred trigger allows late transaction insertion" do
      transaction_with_simulated_commit(fn ->
        # deferred_rabbits have a trigger with INITIALLY DEFERRED constraint, so we can insert
        # a record before inserting the transaction.
        insert_jack("deferred_rabbits")
        insert_transaction()
      end)

      assert [%{"table_name" => "deferred_rabbits"}] = select_changes()
    end

    test "initially deferred trigger still requires a transaction to be inserted" do
      msg =
        "ERROR 23503 (foreign_key_violation) INSERT on table public.deferred_rabbits " <>
          "without prior INSERT into carbonite_default.transactions"

      assert_raise Postgrex.Error, msg, fn ->
        transaction_with_simulated_commit(fn ->
          insert_jack("deferred_rabbits")
        end)
      end

      assert select_rabbits("deferred_rabbits") == []
    end
  end

  describe "default mode / override mode" do
    test "override mode reverses the default mode" do
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET override_xact_id = pg_current_xact_id();
        """)

        insert_jack()
      end)

      assert select_changes() == []
    end

    test "default mode can be set to ignore" do
      # This test exists because we had a bug with the ignore mode
      # when the override_xact_id was NULL
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET mode = 'ignore';
        """)

        insert_jack()
      end)

      assert select_changes() == []
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

  describe "filtered columns" do
    test "appear as [FILTERED] in the data" do
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET filtered_columns = '{name}';
        """)

        insert_transaction()
        insert_jack()
      end)

      assert [%{"data" => %{"name" => "[FILTERED]"}}] = select_changes()
    end

    test "appear as [FILTERED] in the changed_from" do
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET filtered_columns = '{name}';
        """)

        insert_transaction()
        insert_jack()
        query!("UPDATE rabbits SET name = 'Jane' WHERE name = 'Jack';")
      end)

      assert [
               _insert,
               %{"changed_from" => %{"name" => "[FILTERED]"}}
             ] = select_changes()
    end

    test "unknown columns in filtered_columns do not affect the result" do
      TestRepo.transaction(fn ->
        query!("""
        UPDATE carbonite_default.triggers SET filtered_columns = '{doesnotexist}';
        """)

        insert_transaction()
        insert_jack()
      end)

      assert [%{"data" => data}] = select_changes()
      refute Map.has_key?(data, "doesnotexist")
    end
  end
end
