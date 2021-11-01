# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TransactionTest do
  use Carbonite.APICase, async: true
  import Carbonite.Transaction

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
end
