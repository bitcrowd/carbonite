# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Multi do
  @moduledoc """
  This module provides functions for dealing with audit trails in the context of Ecto.Multi.
  """

  @moduledoc since: "0.2.0"

  import Carbonite, only: [default_prefix: 0]
  import Ecto.Query, only: [from: 2]
  alias Carbonite.{Transaction, Trigger}
  alias Ecto.Multi

  @type prefix :: binary() | atom()
  @type params :: map()

  @type insert_transaction_option :: {:carbonite_prefix, prefix()} | {:params, map()}

  @doc """
  Adds an insert operation for a `Carbonite.Transaction` to an `Ecto.Multi`.

  ## Options

  * `name` the name for the multi step, defaults to `:carbonite_transaction`
  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `params` map of params for the `Carbonite.Transaction` (e.g., `:meta`)

  ## Multiple inserts in the same transaction

  Normally, you should have exactly one `insert_transaction/3` call per database transaction. In
  practise, there are two scenarios in this function may be called multiple times:

  1. If an operation A, which calls `insert_transaction/3`, sometimes is nested within an outer
     operation B, which also calls `insert_transaction/3`.
  2. In tests using Ecto's SQL sandbox, subsequent calls to transactional operations (even to the
     same operation twice) are wrapped inside the overarching test transaction, and hence also
     effectively call `insert_transaction/3` within the same transaction.

  While the first scenario can be resolved using appropriate control flow (e.g. by conditionally
  disabling the inner `insert_transaction/3` call), the second scenario is quite common and often
  unavoidable.

  Therefore, `insert_transaction/3` **ignores** subsequent calls within the same database
  transaction (equivalent to `ON CONFLICT DO NOTHING`), **discarding metadata** passed to all
  calls but the first.
  """
  @doc since: "0.2.0"
  @spec insert_transaction(Multi.t()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params(), [insert_transaction_option()]) :: Multi.t()
  def insert_transaction(%Multi{} = multi, params \\ %{}, opts \\ []) do
    name = Keyword.get(opts, :name, :carbonite_transaction)
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    # NOTE: ON CONFLICT DO NOTHING does not combine with RETURNING, so we're forcing an UPDATE.

    Multi.insert(multi, name, fn _state -> Transaction.changeset(params) end,
      prefix: carbonite_prefix,
      on_conflict: {:replace, [:id]},
      conflict_target: [:id],
      returning: true
    )
  end

  @type override_mode_option :: {:carbonite_prefix, prefix()}

  @doc """
  Sets the current transaction to "override mode" for all tables in a translation log.
  """
  @doc since: "0.2.0"
  @spec override_mode(Multi.t(), [override_mode_option()]) :: Multi.t()
  def override_mode(%Multi{} = multi, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    query =
      from(t in Trigger,
        update: [set: [override_transaction_id: fragment("pg_current_xact_id()")]]
      )

    Multi.update_all(multi, :carbonite_triggers, fn _state -> query end, [],
      prefix: carbonite_prefix
    )
  end
end
