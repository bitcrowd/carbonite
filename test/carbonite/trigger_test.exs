defmodule Carbonite.TriggerTest do
  use Carbonite.APICase, async: true
  alias Carbonite.{TestRepo, Trigger}
  alias Ecto.Adapters.SQL

  describe "Schema" do
    test "uses the default carbonite_prefix" do
      {sql, _} = SQL.to_sql(:all, TestRepo, Trigger)
      assert String.contains?(sql, "\"carbonite_default\".\"triggers\"")
    end
  end
end
