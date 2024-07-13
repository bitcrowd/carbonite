# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.APICase do
  @moduledoc false

  use ExUnit.CaseTemplate
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [order_by: 2]
  alias Carbonite.{Query, TestRepo, Transaction}
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Carbonite.APICase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Carbonite.TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  def insert_past_transactions(_) do
    transactions =
      [
        %Transaction{id: 100_000, inserted_at: hours_ago(3)},
        %Transaction{id: 200_000, inserted_at: hours_ago(2)},
        %Transaction{id: 300_000, inserted_at: hours_ago(1)}
      ]
      |> Enum.map(fn tx ->
        TestRepo.insert!(tx, prefix: Carbonite.default_prefix())
      end)

    %{transactions: transactions}
  end

  def insert_transaction_in_alternate_schema(_) do
    transaction_on_alternate_schema =
      TestRepo.insert!(%Transaction{id: 666, inserted_at: hours_ago(1)},
        prefix: "alternate_test_schema"
      )

    %{transaction_on_alternate_schema: transaction_on_alternate_schema}
  end

  defp hours_ago(n) do
    DateTime.utc_now() |> DateTime.add(n * -3600)
  end

  def get_rabbits_outbox do
    "rabbits"
    |> Query.outbox()
    |> TestRepo.one!()
  end

  def update_rabbits_outbox(attrs) do
    get_rabbits_outbox()
    |> change(attrs)
    |> TestRepo.update!()
  end

  def update_alternate_outbox(attrs) do
    "alternate_outbox"
    |> Query.outbox(carbonite_prefix: "alternate_test_schema")
    |> TestRepo.one!()
    |> change(attrs)
    |> TestRepo.update!()
  end

  def get_transactions(opts \\ []) do
    opts
    |> Query.transactions()
    |> order_by({:asc, :id})
    |> TestRepo.all()
  end

  def ids(set), do: set |> Enum.map(& &1.id) |> Enum.sort()
end
