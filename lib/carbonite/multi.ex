# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Multi do
  @moduledoc """
  This module provides functions for dealing with audit trails in the context of Ecto.Multi.
  """

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

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `params` map of params for the `Carbonite.Transaction` (e.g., `:meta`)
  """
  @doc since: "0.1.1"
  @spec insert_transaction(Multi.t()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params(), [insert_transaction_option()]) :: Multi.t()
  def insert_transaction(%Multi{} = multi, params \\ %{}, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    Multi.insert(multi, :carbonite_transaction, fn _state -> Transaction.changeset(params) end,
      prefix: carbonite_prefix,
      returning: [:id]
    )
  end

  @type override_mode_option :: {:carbonite_prefix, prefix()}

  @doc """
  Sets the current transaction to "override mode" for all tables in a translation log.
  """
  @doc since: "0.1.1"
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
