# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Multi do
  @moduledoc """
  This module provides functions for dealing with audit trails in the context of Ecto.Multi.
  """

  @moduledoc since: "0.2.0"

  alias Ecto.Multi

  @type prefix :: binary()
  @type params :: map()

  @type insert_transaction_option :: {:carbonite_prefix, prefix()}

  @doc """
  Adds an insert operation for a `Carbonite.Transaction` to an `Ecto.Multi`.

  See `Carbonite.insert_transaction/3` for options.
  """
  @doc since: "0.2.0"
  @spec insert_transaction(Multi.t()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params(), [insert_transaction_option()]) :: Multi.t()
  def insert_transaction(%Multi{} = multi, params \\ %{}, opts \\ []) do
    Multi.run(multi, :carbonite_transaction, fn repo, _state ->
      Carbonite.insert_transaction(repo, params, opts)
    end)
  end
end
