# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Multi do
  @moduledoc """
  This module provides functions for dealing with audit trails in the context of Ecto.Multi.
  """

  @moduledoc since: "0.2.0"

  alias Carbonite.Trigger
  alias Ecto.Multi

  @type prefix :: binary()
  @type params :: map()

  @type prefix_option :: {:carbonite_prefix, prefix()}

  @doc """
  Adds an insert operation for a `Carbonite.Transaction` to an `Ecto.Multi`.

  Multi step is called `:carbonite_transaction` if no `:carbonite_prefix` option
  is given, otherwise `{:carbonite_transaction, <prefix>}`.

  See `Carbonite.insert_transaction/3` for options.

  ## Example

      Ecto.Multi.new()
      |> Carbonite.Multi.insert_transaction(%{meta: %{type: "create_rabbit"}})
      |> Ecto.Multi.insert(:rabbit, fn _ -> Rabbit.changeset(%{}) end)
  """
  @doc since: "0.2.0"
  @spec insert_transaction(Multi.t()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params()) :: Multi.t()
  @spec insert_transaction(Multi.t(), params(), [prefix_option()]) :: Multi.t()
  def insert_transaction(%Multi{} = multi, params \\ %{}, opts \\ []) do
    name =
      if carbonite_prefix = Keyword.get(opts, :carbonite_prefix) do
        {:carbonite_transaction, carbonite_prefix}
      else
        :carbonite_transaction
      end

    Multi.run(multi, name, fn repo, _state ->
      Carbonite.insert_transaction(repo, params, opts)
    end)
  end

  @doc """
  Adds a operation to an `Ecto.Multi` to fetch the changes of the current transaction.

  Useful for returning all transaction changes to the caller.

  Multi step is called `:carbonite_changes`.

  See `Carbonite.fetch_changes/2` for options.

  ## Example

      Ecto.Multi.new()
      |> Carbonite.Multi.insert_transaction(%{meta: %{type: "create_rabbit"}})
      |> Ecto.Multi.insert(:rabbit, fn _ -> Rabbit.changeset(%{}) end)
      |> Carbonite.Multi.fetch_changes()
  """
  @doc since: "0.5.0"
  @spec fetch_changes(Multi.t()) :: Multi.t()
  @spec fetch_changes(Multi.t(), [prefix_option()]) :: Multi.t()
  def fetch_changes(%Multi{} = multi, opts \\ []) do
    Multi.run(multi, :carbonite_changes, fn repo, _state ->
      Carbonite.fetch_changes(repo, opts)
    end)
  end

  @doc """
  Sets the current transaction to "override mode" for all tables in the audit log.

  See `Carbonite.override_mode/2` for options.
  """
  @doc since: "0.2.0"
  @spec override_mode(Multi.t()) :: Multi.t()
  @spec override_mode(Multi.t(), [{:to, Trigger.mode()} | prefix_option()]) :: Multi.t()
  def override_mode(%Multi{} = multi, opts \\ []) do
    Multi.run(multi, :carbonite_triggers, fn repo, _state ->
      {:ok, Carbonite.override_mode(repo, opts)}
    end)
  end
end
