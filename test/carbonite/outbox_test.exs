# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.OutboxTest do
  use Carbonite.APICase, async: true
  import Carbonite.Outbox
  alias Carbonite.Outbox

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
end
