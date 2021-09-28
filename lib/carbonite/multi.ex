# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Multi do
  @moduledoc """
  This module provides functions for dealing with transaction logs in the context of Ecto.Multi.
  """

  import Carbonite, only: [default_prefix: 0]
  alias Carbonite.Transaction
  alias Ecto.Multi

  @type prefix :: binary() | atom()
  @type params :: map()
  @type insert_transaction_option :: {:carbonite_prefix, prefix()} | {:params, map()}

  @doc """
  Adds an insert operation for a `Carbonite.Transaction` to an `Ecto.Multi`.

  ## Options

  * `carbonite_prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
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
end
