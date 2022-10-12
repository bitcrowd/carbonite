# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.ChangeTest do
  use Carbonite.APICase, async: true
  alias Carbonite.{Change, TestRepo}
  alias Ecto.Adapters.SQL

  describe "Schema" do
    test "uses the default carbonite_prefix" do
      {sql, _} = SQL.to_sql(:all, TestRepo, Change)
      assert String.contains?(sql, ~s("carbonite_default"."changes"))
    end
  end

  describe "Jason.Encoder implementation" do
    test "Carbonite.Change can be encoded to JSON" do
      json =
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
        |> Jason.encode!()
        |> Jason.decode!()

      assert json ==
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
    end
  end
end
