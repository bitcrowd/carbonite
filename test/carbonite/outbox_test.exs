# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.OutboxTest do
  use Carbonite.APICase, async: true
  import Carbonite.Outbox
  alias Carbonite.{Outbox, TestRepo}
  alias Ecto.Adapters.SQL

  describe "changeset/2" do
    test "casts attributes" do
      cs = changeset(%Outbox{}, %{last_transaction_id: 500_000, memo: %{"foo" => "bar"}})
      assert cs.valid?
      assert cs.changes.last_transaction_id == 500_000
      assert cs.changes.memo == %{"foo" => "bar"}
    end

    test "requires presence of memo" do
      cs = changeset(%Outbox{}, %{last_transaction_id: 500_000, memo: nil})
      refute cs.valid?
      assert [{:memo, {_msg, [validation: :required]}}] = cs.errors
    end
  end

  describe "Schema" do
    test "uses the default carbonite_prefix" do
      {sql, _} = SQL.to_sql(:all, TestRepo, Outbox)
      assert String.contains?(sql, ~s("carbonite_default"."outboxes"))
    end
  end
end
